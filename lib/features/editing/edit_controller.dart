import 'package:cim_forge/features/editing/edit_journal.dart';
import 'package:cim_forge/features/editing/edit_validator.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/xml_patch/xml_patcher.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter/foundation.dart';

@immutable
class EditTarget {
  const EditTarget.attribute({
    required this.elementId,
    required String attribute,
  }) : isAssociation = false,
       name = attribute;

  const EditTarget.association({
    required this.elementId,
    required String association,
  }) : isAssociation = true,
       name = association;

  final String elementId;
  final String name;
  final bool isAssociation;

  @override
  bool operator ==(Object other) =>
      other is EditTarget &&
      other.elementId == elementId &&
      other.name == name &&
      other.isAssociation == isAssociation;

  @override
  int get hashCode => Object.hash(elementId, name, isAssociation);
}

class EditApplyException implements Exception {
  EditApplyException(this.issues);
  final List<ValidationIssue> issues;
  @override
  String toString() =>
      'EditApplyException: ${issues.map((i) => i.message).join("; ")}';
}

/// Owns the live edit state for one open model file:
///   - The original parsed [ObjectGraph] (immutable here — `graph` is the
///     snapshot the spans were computed against).
///   - The [EditJournal] driving undo / redo / batch grouping.
///   - A pending-values map projecting the journal's undo-stack onto the
///     graph; whenever the journal moves, the map is recomputed.
///   - Synchronization with the SQLite index so view queries see the live
///     value of every edited attribute / association.
///
/// On [renderPatchedSource] the pending edits are projected to [TextEdit]s
/// and applied to the source string; callers receive the new source and are
/// responsible for writing it to disk and supplying a fresh [ObjectGraph].
class EditController extends ChangeNotifier {
  EditController({
    required this.graph,
    required this.metamodel,
    required this.database,
    required this.fileId,
  }) : _journal = EditJournal(),
       _validator = EditValidator(metamodel: metamodel, graph: graph) {
    _journal.addListener(_onJournalChanged);
  }

  final ObjectGraph graph;
  final Metamodel metamodel;
  final AppDatabase database;
  final int fileId;

  final EditJournal _journal;
  final EditValidator _validator;

  /// Pending values projected from the journal's undo-stack. A key whose
  /// value matches the original-source value is omitted (no patch needed).
  final Map<EditTarget, String> _pending = {};

  EditJournal get journal => _journal;

  /// Live current value of a scalar attribute — pending value if present,
  /// otherwise the value as parsed from source. Returns null if the
  /// attribute is absent from the element entirely.
  String? currentAttribute(String elementId, String attributeName) {
    final target = EditTarget.attribute(
      elementId: elementId,
      attribute: attributeName,
    );
    if (_pending.containsKey(target)) return _pending[target];
    final el = graph.elementById(elementId);
    return el?.attribute(attributeName)?.value;
  }

  /// Live current target id of an association.
  String? currentAssociation(String elementId, String associationName) {
    final target = EditTarget.association(
      elementId: elementId,
      association: associationName,
    );
    if (_pending.containsKey(target)) return _pending[target];
    final el = graph.elementById(elementId);
    return el?.association(associationName)?.targetId;
  }

  /// Applies [op] after schema validation. Throws [EditApplyException] when
  /// the operation is invalid; the caller surfaces issues to the user.
  void apply(EditOperation op) {
    final issues = _validator.validate(op);
    if (issues.isNotEmpty) throw EditApplyException(issues);
    _journal.push(op);
    // _onJournalChanged runs from the journal listener — keeps state coherent.
  }

  /// Begin a batch group on the journal. Operations applied via [apply]
  /// inside the begin/end will commit as one undo step (FR-3.2).
  void beginGroup(String label) => _journal.beginGroup(label);
  void endGroup() => _journal.endGroup();

  /// Reverses the most recent applied operation (or composite). Throws
  /// when nothing is undoable.
  void undo() {
    if (!_journal.canUndo) throw StateError('nothing to undo');
    _journal.undo();
  }

  /// Re-applies the most recently undone operation.
  void redo() {
    if (!_journal.canRedo) throw StateError('nothing to redo');
    _journal.redo();
  }

  /// True when the journal holds any applied edits (i.e. edits that would
  /// produce text patches on save).
  bool get hasPendingEdits => _pending.isNotEmpty;

  /// Returns the live pending state as a read-only view.
  Map<EditTarget, String> get pendingValues =>
      Map.unmodifiable(_pending);

  /// Produces [TextEdit]s targeting `graph.source` that, when applied via
  /// `applyTextEdits`, yield a source string equivalent to the live state
  /// of the model.
  List<TextEdit> pendingTextEdits() {
    final out = <TextEdit>[];
    for (final entry in _pending.entries) {
      final target = entry.key;
      final newValue = entry.value;
      final element = graph.elementById(target.elementId);
      if (element == null) continue;
      if (target.isAssociation) {
        final assoc = element.association(target.name);
        if (assoc == null) continue;
        out.add(
          TextEdit(
            start: assoc.targetSpan.start,
            stop: assoc.targetSpan.stop,
            replacement:
                'rdf:resource="${_resourceLiteralFor(newValue)}"',
          ),
        );
      } else {
        final attr = element.attribute(target.name);
        if (attr == null) continue;
        out.add(
          TextEdit(
            start: attr.textSpan.start,
            stop: attr.textSpan.stop,
            replacement: newValue,
          ),
        );
      }
    }
    return out;
  }

  /// Applies all pending edits to `graph.source` and returns the patched
  /// source. Callers are responsible for writing this to disk and
  /// constructing a fresh [EditController] against the reparsed graph.
  String renderPatchedSource() =>
      applyTextEdits(graph.source, pendingTextEdits());

  @override
  void dispose() {
    _journal
      ..removeListener(_onJournalChanged)
      ..dispose();
    super.dispose();
  }

  // --- internals ---------------------------------------------------------

  void _onJournalChanged() {
    _recomputePendingFromJournal();
    _syncIndex();
    notifyListeners();
  }

  void _recomputePendingFromJournal() {
    _pending.clear();
    for (final op in _journal.undoStack) {
      _replayOpIntoPending(op);
    }
    // Prune entries that match the original-source value.
    _pending.removeWhere((target, value) {
      final originalValue = _originalValue(target);
      return originalValue != null && originalValue == value;
    });
  }

  void _replayOpIntoPending(EditOperation op) {
    switch (op) {
      case final SetAttributeValueOp s:
        final target = EditTarget.attribute(
          elementId: s.elementId,
          attribute: s.attributeName,
        );
        _pending[target] = s.newValue;
      case final SetAssociationTargetOp s:
        final target = EditTarget.association(
          elementId: s.elementId,
          association: s.associationName,
        );
        _pending[target] = s.newTargetId;
      case final CompositeOp c:
        for (final child in c.children) {
          _replayOpIntoPending(child);
        }
    }
  }

  String? _originalValue(EditTarget target) {
    final element = graph.elementById(target.elementId);
    if (element == null) return null;
    if (target.isAssociation) {
      return element.association(target.name)?.targetId;
    }
    return element.attribute(target.name)?.value;
  }

  /// Replaces the SQLite-index rows that the pending map mutates so view
  /// queries reflect the live state. We don't try to be clever here — for
  /// each edited target we issue a small UPDATE; the indexer's batch-insert
  /// path is for cold loads.
  void _syncIndex() {
    final db = database.raw..execute('BEGIN');
    try {
      // First, restore any attribute / association rows we may have edited
      // in a previous tick that no longer have a pending value. To keep the
      // bookkeeping minimal, we re-derive every edited target's current
      // live value (pending or original) and UPSERT it.
      final edited = _editedTargets();
      for (final target in edited) {
        if (target.isAssociation) {
          final element = graph.elementById(target.elementId);
          final assoc = element?.association(target.name);
          if (assoc == null) continue;
          final live = currentAssociation(target.elementId, target.name);
          db.execute(
            'UPDATE associations SET dst_element_id = ? '
            'WHERE src_element_id = ? AND name = ?',
            [live, target.elementId, target.name],
          );
        } else {
          final element = graph.elementById(target.elementId);
          final attr = element?.attribute(target.name);
          if (attr == null) continue;
          final live = currentAttribute(target.elementId, target.name);
          db.execute(
            'UPDATE attributes SET value = ? '
            'WHERE element_id = ? AND name = ?',
            [live, target.elementId, target.name],
          );
        }
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Returns the union of targets that *might* differ from source — every
  // target the journal has ever touched. We don't currently track this
  // explicitly; instead derive from journal entries.
  Set<EditTarget> _editedTargets() {
    final out = <EditTarget>{};
    void walk(EditOperation op) {
      switch (op) {
        case final SetAttributeValueOp s:
          out.add(EditTarget.attribute(
            elementId: s.elementId,
            attribute: s.attributeName,
          ));
        case final SetAssociationTargetOp s:
          out.add(EditTarget.association(
            elementId: s.elementId,
            association: s.associationName,
          ));
        case final CompositeOp c:
          c.children.forEach(walk);
      }
    }

    for (final entry in [..._journal.undoStack, ..._journal.redoStack]) {
      walk(entry);
    }
    return out;
  }

  String _resourceLiteralFor(String targetId) {
    // CIM ecosystems use either `#localId` (intra-file) or `urn:uuid:...`
    // (cross-file). We preserve the form that the target id implies — if it
    // looks like a urn or starts with `http`, keep it as-is; otherwise add
    // the `#` fragment prefix.
    if (targetId.startsWith('urn:') ||
        targetId.startsWith('http:') ||
        targetId.startsWith('https:')) {
      return targetId;
    }
    return '#$targetId';
  }
}
