import 'package:meta/meta.dart';

/// Cardinality range on an attribute or association.
@immutable
class Cardinality {
  const Cardinality({required this.min, required this.max});

  /// 0..1 — at most one value.
  static const optional = Cardinality(min: 0, max: 1);

  /// 1..1 — exactly one value.
  static const required = Cardinality(min: 1, max: 1);

  /// 0..* — any number including zero.
  static const many = Cardinality(min: 0, max: -1);

  /// 1..* — at least one value.
  static const oneOrMore = Cardinality(min: 1, max: -1);

  /// Minimum count; 0 means optional.
  final int min;

  /// Maximum count; -1 means unbounded.
  final int max;

  bool get isUnbounded => max == -1;
  bool get isOptional => min == 0;
  bool get isToOne => max == 1;

  @override
  bool operator ==(Object other) =>
      other is Cardinality && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => '$min..${isUnbounded ? "*" : max}';
}

/// A scalar attribute on a CIM class — a property carrying a literal value
/// (string, number, enumeration, etc.). Associations to other classes are
/// modeled separately by [CimAssociation].
@immutable
class CimAttribute {
  const CimAttribute({
    required this.name,
    required this.dataType,
    required this.cardinality,
  });

  /// Bare attribute name as it appears on the class (without the class-name
  /// prefix). CIM RDF/XML serializes attributes as `<ClassName.attrName>`.
  final String name;

  /// Logical type — primitive (`String`, `Float`, ...) or an enumeration name.
  /// We deliberately model this as an opaque string for profile-agnosticism
  /// (FR-1.2); the schema loader resolves it to a [CimEnumeration] when
  /// possible.
  final String dataType;

  final Cardinality cardinality;

  @override
  bool operator ==(Object other) =>
      other is CimAttribute &&
      other.name == name &&
      other.dataType == dataType &&
      other.cardinality == cardinality;

  @override
  int get hashCode => Object.hash(name, dataType, cardinality);
}

/// An association from one CIM class to another. CIM RDF/XML serializes
/// associations as either an inline child element (`<Class.assoc>...</...>`)
/// or a `rdf:resource` pointer.
@immutable
class CimAssociation {
  const CimAssociation({
    required this.name,
    required this.targetClass,
    required this.cardinality,
  });

  final String name;
  final String targetClass;
  final Cardinality cardinality;

  @override
  bool operator ==(Object other) =>
      other is CimAssociation &&
      other.name == name &&
      other.targetClass == targetClass &&
      other.cardinality == cardinality;

  @override
  int get hashCode => Object.hash(name, targetClass, cardinality);
}

/// A CIM class — name, parent (if any), and the attributes / associations
/// declared on this class itself (NOT inherited). Use
/// [Metamodel.attributesOf] / [Metamodel.associationsOf] to walk inheritance.
@immutable
class CimClass {
  const CimClass({
    required this.name,
    this.parent,
    this.ownAttributes = const [],
    this.ownAssociations = const [],
  });

  final String name;
  final String? parent;
  final List<CimAttribute> ownAttributes;
  final List<CimAssociation> ownAssociations;
}

/// A CIM enumeration — a named set of allowed string members.
@immutable
class CimEnumeration {
  const CimEnumeration({required this.name, required this.members});

  final String name;
  final List<String> members;
}

/// The in-memory CIM metamodel. Profile-agnostic (FR-1.2) — no class or
/// attribute names are compiled in.
class Metamodel {
  Metamodel({
    required Map<String, CimClass> classes,
    Map<String, CimEnumeration> enumerations = const {},
  }) : _classes = Map.unmodifiable(classes),
       _enumerations = Map.unmodifiable(enumerations);

  final Map<String, CimClass> _classes;
  final Map<String, CimEnumeration> _enumerations;

  Iterable<CimClass> get classes => _classes.values;
  Iterable<CimEnumeration> get enumerations => _enumerations.values;

  CimClass? classByName(String name) => _classes[name];
  CimEnumeration? enumByName(String name) => _enumerations[name];

  /// All attributes of [className] including inherited ones, ordered by
  /// definition depth (root parent first). Throws [ArgumentError] if the
  /// class is unknown.
  List<CimAttribute> attributesOf(String className) {
    final chain = _ancestorChain(className);
    return [for (final c in chain) ...c.ownAttributes];
  }

  /// All associations of [className] including inherited ones.
  List<CimAssociation> associationsOf(String className) {
    final chain = _ancestorChain(className);
    return [for (final c in chain) ...c.ownAssociations];
  }

  /// Returns the inheritance chain from the root parent down to [className]
  /// (root first, self last). Detects cycles defensively.
  List<CimClass> ancestorChain(String className) =>
      List.unmodifiable(_ancestorChain(className));

  List<CimClass> _ancestorChain(String className) {
    final cls = _classes[className];
    if (cls == null) {
      throw ArgumentError.value(className, 'className', 'unknown class');
    }
    final chain = <CimClass>[];
    final seen = <String>{};
    var cursor = cls;
    while (true) {
      if (!seen.add(cursor.name)) {
        throw StateError('inheritance cycle through ${cursor.name}');
      }
      chain.insert(0, cursor);
      final parent = cursor.parent;
      if (parent == null) break;
      final parentCls = _classes[parent];
      if (parentCls == null) break;
      cursor = parentCls;
    }
    return chain;
  }
}
