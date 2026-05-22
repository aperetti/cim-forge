import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:meta/meta.dart';

@immutable
class ViewValidationIssue {
  const ViewValidationIssue(this.path, this.message);
  final String path;
  final String message;
  @override
  String toString() => '$path: $message';
}

/// Validates a [ViewDefinition] against a [Metamodel] (FR-1.4 + FR-2.4 —
/// views that ride in the repo must continue to make sense when the schema
/// they reference changes). Empty list = the view loads cleanly.
class ViewValidator {
  ViewValidator(this.metamodel);

  final Metamodel metamodel;

  List<ViewValidationIssue> validate(ViewDefinition view) {
    final issues = <ViewValidationIssue>[];

    final base = metamodel.classByName(view.baseClass);
    if (base == null) {
      issues.add(
        ViewValidationIssue(
          'baseClass',
          'Unknown class "${view.baseClass}"',
        ),
      );
      // Without a base class, the rest of the checks make no sense.
      return issues;
    }

    for (var i = 0; i < view.columns.length; i++) {
      _validatePath(
        path: view.columns[i].path,
        fromClass: view.baseClass,
        location: 'columns[$i]',
        issues: issues,
      );
    }

    for (var i = 0; i < view.filters.length; i++) {
      _validatePath(
        path: view.filters[i].path,
        fromClass: view.baseClass,
        location: 'filters[$i]',
        issues: issues,
      );
    }

    for (var i = 0; i < view.sort.length; i++) {
      _validatePath(
        path: view.sort[i].path,
        fromClass: view.baseClass,
        location: 'sort[$i]',
        issues: issues,
      );
    }

    for (var i = 0; i < view.inclusions.length; i++) {
      _validateInclusion(
        view.inclusions[i],
        i,
        view.baseClass,
        issues,
      );
    }

    return issues;
  }

  void _validatePath({
    required List<String> path,
    required String fromClass,
    required String location,
    required List<ViewValidationIssue> issues,
  }) {
    if (path.isEmpty) {
      issues.add(ViewValidationIssue(location, 'path is empty'));
      return;
    }

    var current = fromClass;
    for (var i = 0; i < path.length - 1; i++) {
      final hop = path[i];
      final assoc =
          metamodel.associationsOf(current).where((a) => a.name == hop);
      if (assoc.isEmpty) {
        issues.add(
          ViewValidationIssue(
            '$location[$i]',
            '$current has no association "$hop"',
          ),
        );
        return;
      }
      current = assoc.first.targetClass;
    }

    final attrName = path.last;
    final attr = metamodel
        .attributesOf(current)
        .where((a) => a.name == attrName);
    if (attr.isEmpty) {
      issues.add(
        ViewValidationIssue(
          location,
          '$current has no attribute "$attrName"',
        ),
      );
    }
  }

  void _validateInclusion(
    CompositeInclusion inclusion,
    int index,
    String baseClass,
    List<ViewValidationIssue> issues,
  ) {
    final location = 'inclusions[$index]';

    final childCls = metamodel.classByName(inclusion.childClass);
    if (childCls == null) {
      issues.add(
        ViewValidationIssue(
          '$location.childClass',
          'Unknown class "${inclusion.childClass}"',
        ),
      );
      return; // can't check attribute paths without the child class
    }

    final assoc = _resolveAssociation(
      base: baseClass,
      child: inclusion.childClass,
      assocName: inclusion.association,
      direction: inclusion.direction,
    );
    if (assoc == null) {
      issues.add(
        ViewValidationIssue(
          '$location.association',
          'No "${inclusion.association}" association '
          '(${inclusion.direction.name}) between '
          '$baseClass and ${inclusion.childClass}',
        ),
      );
      return;
    }

    final orderAttr = metamodel
        .attributesOf(inclusion.childClass)
        .where((a) => a.name == inclusion.orderBy);
    if (orderAttr.isEmpty) {
      issues.add(
        ViewValidationIssue(
          '$location.orderBy',
          '${inclusion.childClass} has no attribute '
          '"${inclusion.orderBy}"',
        ),
      );
    }

    final legalAttrs =
        metamodel.attributesOf(inclusion.childClass).map((a) => a.name).toSet();
    for (var i = 0; i < inclusion.attributes.length; i++) {
      if (!legalAttrs.contains(inclusion.attributes[i])) {
        issues.add(
          ViewValidationIssue(
            '$location.attributes[$i]',
            '${inclusion.childClass} has no attribute '
            '"${inclusion.attributes[i]}"',
          ),
        );
      }
    }
  }

  CimAssociation? _resolveAssociation({
    required String base,
    required String child,
    required String assocName,
    required InclusionDirection direction,
  }) {
    final declaringClass =
        direction == InclusionDirection.forward ? base : child;
    final targetClass =
        direction == InclusionDirection.forward ? child : base;
    final found = metamodel
        .associationsOf(declaringClass)
        .where((a) => a.name == assocName);
    if (found.isEmpty) return null;
    final assoc = found.first;
    // Target must be the target class (or an ancestor — childClass may be a
    // subclass of the declared target).
    if (!_isOrAncestor(targetClass, assoc.targetClass)) return null;
    return assoc;
  }

  bool _isOrAncestor(String specific, String ancestorOrSame) {
    if (specific == ancestorOrSame) return true;
    final cls = metamodel.classByName(specific);
    if (cls == null) return false;
    return metamodel
        .ancestorChain(specific)
        .any((c) => c.name == ancestorOrSame);
  }
}
