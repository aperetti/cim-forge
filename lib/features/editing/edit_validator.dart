import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:meta/meta.dart';

@immutable
class ValidationIssue {
  const ValidationIssue(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Validates [EditOperation]s against the [Metamodel] and [ObjectGraph]
/// (FR-3.7). Issues are returned as a list — empty means the operation is
/// legal. Multiple issues per op are reported when they're independent
/// (e.g. unknown attribute AND invalid value would surface both).
class EditValidator {
  EditValidator({required this.metamodel, required this.graph});

  final Metamodel metamodel;
  final ObjectGraph graph;

  List<ValidationIssue> validate(EditOperation op) {
    return switch (op) {
      final SetAttributeValueOp s => _validateSetAttribute(s),
      final SetAssociationTargetOp s => _validateSetAssociation(s),
      final CompositeOp c => [
        for (final child in c.children) ...validate(child),
      ],
    };
  }

  List<ValidationIssue> _validateSetAttribute(SetAttributeValueOp op) {
    final element = graph.elementById(op.elementId);
    if (element == null) {
      return [ValidationIssue('Unknown element "${op.elementId}"')];
    }
    final attrs = metamodel.attributesOf(element.className);
    final attr = attrs.where((a) => a.name == op.attributeName).firstOrNull;
    if (attr == null) {
      return [
        ValidationIssue(
          '${element.className} has no attribute "${op.attributeName}"',
        ),
      ];
    }
    final issues = <ValidationIssue>[];
    final typeIssue = _validateValueAgainstType(op.newValue, attr.dataType);
    if (typeIssue != null) issues.add(typeIssue);
    return issues;
  }

  List<ValidationIssue> _validateSetAssociation(SetAssociationTargetOp op) {
    final element = graph.elementById(op.elementId);
    if (element == null) {
      return [ValidationIssue('Unknown element "${op.elementId}"')];
    }
    final assocs = metamodel.associationsOf(element.className);
    final assoc =
        assocs.where((a) => a.name == op.associationName).firstOrNull;
    if (assoc == null) {
      return [
        ValidationIssue(
          '${element.className} has no association "${op.associationName}"',
        ),
      ];
    }
    final target = graph.elementById(op.newTargetId);
    if (target == null) {
      return [
        ValidationIssue(
          'Target element "${op.newTargetId}" does not exist in the graph',
        ),
      ];
    }
    // The target must conform to the association's declared target class
    // (or any subclass of it). Walk the target's ancestor chain.
    if (!_isOrInheritsFrom(target.className, assoc.targetClass)) {
      return [
        ValidationIssue(
          'Target "${op.newTargetId}" is a ${target.className}; '
          '${op.associationName} expects ${assoc.targetClass}',
        ),
      ];
    }
    return const [];
  }

  bool _isOrInheritsFrom(String className, String ancestor) {
    if (className == ancestor) return true;
    final cls = metamodel.classByName(className);
    if (cls == null) return false;
    // classByName succeeded, so ancestorChain won't throw for unknown class.
    return metamodel
        .ancestorChain(className)
        .any((c) => c.name == ancestor);
  }

  ValidationIssue? _validateValueAgainstType(String value, String type) {
    final normalized = type.toLowerCase();
    switch (normalized) {
      case 'string':
      case 'xsd:string':
        return null;
      case 'float':
      case 'double':
      case 'xsd:float':
      case 'xsd:double':
        if (double.tryParse(value) == null) {
          return ValidationIssue(
            '"$value" is not a valid floating-point number for type $type',
          );
        }
        return null;
      case 'int':
      case 'integer':
      case 'xsd:int':
      case 'xsd:integer':
        if (int.tryParse(value) == null) {
          return ValidationIssue(
            '"$value" is not a valid integer for type $type',
          );
        }
        return null;
      case 'boolean':
      case 'xsd:boolean':
        if (value != 'true' && value != 'false') {
          return ValidationIssue('"$value" is not a boolean (true/false)');
        }
        return null;
    }
    // Otherwise the type may name an enumeration. Permit if unknown — M4
    // accepts user-defined / primitive-extension types without complaint.
    final enumeration = metamodel.enumByName(type);
    if (enumeration != null && !enumeration.members.contains(value)) {
      return ValidationIssue(
        '"$value" is not a member of enumeration $type '
        '(allowed: ${enumeration.members.join(", ")})',
      );
    }
    return null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
