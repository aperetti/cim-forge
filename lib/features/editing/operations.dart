import 'package:meta/meta.dart';

/// Base type for all edit operations. Operations are immutable value records
/// that describe a single mutation along with the prior value(s) needed to
/// undo it. The EditController is what actually applies / inverts them
/// against the object graph + SQLite index + pending patch list.
@immutable
sealed class EditOperation {
  const EditOperation();

  /// Returns the operation that, when applied, undoes this one.
  EditOperation invert();
}

/// Replace the textual value of a scalar attribute on an element.
@immutable
class SetAttributeValueOp extends EditOperation {
  const SetAttributeValueOp({
    required this.elementId,
    required this.attributeName,
    required this.newValue,
    required this.oldValue,
  });

  /// Id of the element carrying the attribute (CimElement.id).
  final String elementId;

  /// Short attribute name (e.g. `name`, `length`). The full
  /// `Class.attrName` form lives on the XML node but the metamodel + journal
  /// address attributes by their short name (consistent with the M3 index).
  final String attributeName;
  final String newValue;
  final String oldValue;

  @override
  SetAttributeValueOp invert() => SetAttributeValueOp(
    elementId: elementId,
    attributeName: attributeName,
    newValue: oldValue,
    oldValue: newValue,
  );

  @override
  bool operator ==(Object other) =>
      other is SetAttributeValueOp &&
      other.elementId == elementId &&
      other.attributeName == attributeName &&
      other.newValue == newValue &&
      other.oldValue == oldValue;

  @override
  int get hashCode =>
      Object.hash(elementId, attributeName, newValue, oldValue);

  @override
  String toString() =>
      'SetAttributeValueOp($elementId.$attributeName: '
      '"$oldValue" -> "$newValue")';
}

/// Retarget an association on an element.
@immutable
class SetAssociationTargetOp extends EditOperation {
  const SetAssociationTargetOp({
    required this.elementId,
    required this.associationName,
    required this.newTargetId,
    required this.oldTargetId,
  });

  final String elementId;
  final String associationName;
  final String newTargetId;
  final String oldTargetId;

  @override
  SetAssociationTargetOp invert() => SetAssociationTargetOp(
    elementId: elementId,
    associationName: associationName,
    newTargetId: oldTargetId,
    oldTargetId: newTargetId,
  );

  @override
  bool operator ==(Object other) =>
      other is SetAssociationTargetOp &&
      other.elementId == elementId &&
      other.associationName == associationName &&
      other.newTargetId == newTargetId &&
      other.oldTargetId == oldTargetId;

  @override
  int get hashCode =>
      Object.hash(elementId, associationName, newTargetId, oldTargetId);

  @override
  String toString() =>
      'SetAssociationTargetOp($elementId.$associationName: '
      '"$oldTargetId" -> "$newTargetId")';
}

/// Group multiple operations into one journal entry — undone or redone as a
/// single step (FR-3.2 batch edits). Applied in order; inverted in reverse.
@immutable
class CompositeOp extends EditOperation {
  const CompositeOp({required this.label, required this.children});

  /// Short user-facing description of what the group does, surfaced in the
  /// undo/redo menu (FR-3.6 needs labelled history eventually).
  final String label;
  final List<EditOperation> children;

  @override
  CompositeOp invert() => CompositeOp(
    label: 'undo: $label',
    children: [for (final op in children.reversed) op.invert()],
  );
}
