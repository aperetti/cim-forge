import 'package:cim_forge/features/editing/operations.dart';
import 'package:flutter/foundation.dart';

/// Ordered log of edit operations. Single source of truth for undo/redo
/// (TR-6.1). The journal records what *has been applied* — applying is the
/// EditController's job.
///
/// State model: `entries[0 .. cursor)` are applied (undo-stack);
/// `entries[cursor .. end)` are undone (redo-stack). [push] truncates the
/// redo tail before adding.
class EditJournal extends ChangeNotifier {
  EditJournal();

  final List<EditOperation> _entries = [];
  int _cursor = 0;

  /// Open group depth. Operations [push]ed while > 0 are buffered into a
  /// pending [CompositeOp] and committed when the outermost group closes.
  int _groupDepth = 0;
  String? _groupLabel;
  final List<EditOperation> _groupBuffer = [];

  /// Operations that have been applied and are eligible for undo.
  Iterable<EditOperation> get undoStack =>
      _entries.take(_cursor);

  /// Operations that have been undone and are eligible for redo.
  Iterable<EditOperation> get redoStack => _entries.skip(_cursor);

  bool get canUndo => _cursor > 0 && _groupDepth == 0;
  bool get canRedo => _cursor < _entries.length && _groupDepth == 0;

  bool get hasPending => _entries.isNotEmpty;

  /// Records [op] as the newest applied entry. Truncates any redo tail
  /// (re-doing after a fresh edit is no longer meaningful).
  ///
  /// When inside a [beginGroup] / [endGroup] block, [op]s are buffered into
  /// a pending [CompositeOp] and only committed on the outermost
  /// [endGroup]. This is how FR-3.2 batch edits get a single undo step.
  void push(EditOperation op) {
    if (_groupDepth > 0) {
      _groupBuffer.add(op);
      return;
    }
    _entries
      ..removeRange(_cursor, _entries.length)
      ..add(op);
    _cursor = _entries.length;
    notifyListeners();
  }

  /// Take the next undo target, advancing the cursor backwards. Returns the
  /// inverse of that operation so the caller can apply it.
  EditOperation undo() {
    if (!canUndo) {
      throw StateError('nothing to undo');
    }
    _cursor--;
    notifyListeners();
    return _entries[_cursor].invert();
  }

  /// Take the next redo target, advancing the cursor forwards. Returns the
  /// operation to re-apply.
  EditOperation redo() {
    if (!canRedo) {
      throw StateError('nothing to redo');
    }
    final op = _entries[_cursor];
    _cursor++;
    notifyListeners();
    return op;
  }

  /// Begin a batch group. Operations pushed before the matching [endGroup]
  /// are buffered and committed as one [CompositeOp].
  void beginGroup(String label) {
    if (_groupDepth == 0) {
      _groupLabel = label;
      _groupBuffer.clear();
    }
    _groupDepth++;
  }

  /// Close the current batch group. The outermost close commits the buffer
  /// as a single [CompositeOp] (or as the single buffered op if there was
  /// only one — avoids a degenerate Composite of length 1).
  void endGroup() {
    if (_groupDepth == 0) {
      throw StateError('endGroup called without matching beginGroup');
    }
    _groupDepth--;
    if (_groupDepth > 0) return;
    if (_groupBuffer.isEmpty) {
      _groupLabel = null;
      return;
    }
    final committed = _groupBuffer.length == 1
        ? _groupBuffer.single
        : CompositeOp(
            label: _groupLabel ?? 'batch',
            children: List.unmodifiable(_groupBuffer),
          );
    _entries
      ..removeRange(_cursor, _entries.length)
      ..add(committed);
    _cursor = _entries.length;
    _groupLabel = null;
    _groupBuffer.clear();
    notifyListeners();
  }

  /// Clear all journal state. After [clear] the entries are gone and
  /// canUndo/canRedo are both false — typically called on project close or
  /// after a successful save.
  void clear() {
    _entries.clear();
    _cursor = 0;
    _groupDepth = 0;
    _groupBuffer.clear();
    _groupLabel = null;
    notifyListeners();
  }
}
