import 'package:cim_forge/features/model/element.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:meta/meta.dart';

@immutable
class AttributeChange {
  const AttributeChange({required this.oldValue, required this.newValue});
  final String? oldValue;
  final String? newValue;

  bool get isAddition => oldValue == null && newValue != null;
  bool get isRemoval => oldValue != null && newValue == null;
  bool get isModification => oldValue != null && newValue != null;
}

@immutable
class AssociationChange {
  const AssociationChange({
    required this.oldTargetId,
    required this.newTargetId,
  });
  final String? oldTargetId;
  final String? newTargetId;

  bool get isAddition => oldTargetId == null && newTargetId != null;
  bool get isRemoval => oldTargetId != null && newTargetId == null;
  bool get isModification => oldTargetId != null && newTargetId != null;
}

@immutable
class ElementDiff {
  const ElementDiff({
    required this.id,
    required this.className,
    required this.attributeChanges,
    required this.associationChanges,
  });

  final String id;
  final String className;

  /// Keyed by attribute short name.
  final Map<String, AttributeChange> attributeChanges;

  /// Keyed by association short name.
  final Map<String, AssociationChange> associationChanges;

  bool get hasChanges =>
      attributeChanges.isNotEmpty || associationChanges.isNotEmpty;
}

/// Structured diff between two parsed [ObjectGraph]s. Lists are sorted by
/// element id for deterministic output and stable review-UI rendering.
@immutable
class SemanticDiff {
  const SemanticDiff({
    required this.added,
    required this.removed,
    required this.modified,
  });

  /// Returns a structured diff between [oldGraph] and [newGraph].
  ///
  /// An element is "added" if its id exists in [newGraph] but not
  /// [oldGraph], "removed" if the opposite. An element with the same id in
  /// both graphs is "modified" iff any of its attributes or associations
  /// differ between the two parses; class changes are surfaced as a
  /// remove + add pair to keep downstream consumers from over-merging
  /// unrelated edits.
  factory SemanticDiff.between(ObjectGraph oldGraph, ObjectGraph newGraph) {
    final oldById = {for (final el in oldGraph.elements) el.id: el};
    final newById = {for (final el in newGraph.elements) el.id: el};

    final added = <CimElement>[];
    final removed = <CimElement>[];
    final modified = <ElementDiff>[];

    final allIds = <String>{...oldById.keys, ...newById.keys}.toList()..sort();
    for (final id in allIds) {
      final before = oldById[id];
      final after = newById[id];

      if (before == null && after != null) {
        added.add(after);
      } else if (before != null && after == null) {
        removed.add(before);
      } else if (before != null && after != null) {
        if (before.className != after.className) {
          removed.add(before);
          added.add(after);
          continue;
        }
        final diff = _diffElement(before, after);
        if (diff.hasChanges) modified.add(diff);
      }
    }

    return SemanticDiff(
      added: List.unmodifiable(added),
      removed: List.unmodifiable(removed),
      modified: List.unmodifiable(modified),
    );
  }

  /// Elements present in the newer graph but not the older one.
  final List<CimElement> added;

  /// Elements present in the older graph but not the newer one.
  final List<CimElement> removed;

  /// Elements present in both with at least one attribute or association
  /// change.
  final List<ElementDiff> modified;

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && modified.isEmpty;
}

ElementDiff _diffElement(CimElement before, CimElement after) {
  final attributeChanges = <String, AttributeChange>{};
  final beforeAttrs = {for (final a in before.attributes) a.shortName: a.value};
  final afterAttrs = {for (final a in after.attributes) a.shortName: a.value};
  final attrNames = <String>{...beforeAttrs.keys, ...afterAttrs.keys}
      .toList()
    ..sort();
  for (final name in attrNames) {
    final oldValue = beforeAttrs[name];
    final newValue = afterAttrs[name];
    if (oldValue != newValue) {
      attributeChanges[name] = AttributeChange(
        oldValue: oldValue,
        newValue: newValue,
      );
    }
  }

  final associationChanges = <String, AssociationChange>{};
  final beforeAssocs = {
    for (final a in before.associations) a.shortName: a.targetId,
  };
  final afterAssocs = {
    for (final a in after.associations) a.shortName: a.targetId,
  };
  final assocNames =
      <String>{...beforeAssocs.keys, ...afterAssocs.keys}.toList()..sort();
  for (final name in assocNames) {
    final oldTarget = beforeAssocs[name];
    final newTarget = afterAssocs[name];
    if (oldTarget != newTarget) {
      associationChanges[name] = AssociationChange(
        oldTargetId: oldTarget,
        newTargetId: newTarget,
      );
    }
  }

  return ElementDiff(
    id: before.id,
    className: before.className,
    attributeChanges: Map.unmodifiable(attributeChanges),
    associationChanges: Map.unmodifiable(associationChanges),
  );
}
