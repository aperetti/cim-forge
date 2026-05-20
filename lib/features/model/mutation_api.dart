import 'package:cim_forge/features/model/element.dart';

/// Interface the M4 edit journal will implement against. Sketched in M2
/// so the typed object graph's mutation surface is journal-shaped from
/// day one; no operations are implemented yet.
abstract interface class ObjectGraphMutationApi {
  /// Set the scalar [attribute]'s value on [element] to [newValue].
  void setAttribute(
    CimElement element,
    ElementAttribute attribute,
    String newValue,
  );

  /// Retarget the association on [element] to point at [newTargetId].
  void setAssociationTarget(
    CimElement element,
    ElementAssociation association,
    String newTargetId,
  );

  /// Add a new CIM element of [className] with id [id] and queue the
  /// pending XML insertion.
  void addElement({required String className, required String id});

  /// Remove [element] from the graph and queue its removal.
  void removeElement(CimElement element);
}
