import 'package:meta/meta.dart';

/// A column in a table view. The [path] is a list of property names walked
/// from the view's base class — the trailing element is the attribute being
/// shown; any preceding elements are association traversals.
///
/// Examples:
///   ColumnDefinition(path: ['name']) → base class's own `name` attribute.
///   ColumnDefinition(path: ['EquipmentContainer', 'name']) → name of the
///     container this element belongs to.
@immutable
class ColumnDefinition {
  /// [path] must be non-empty — callers must enforce this. The check is
  /// performed at the JSON boundary, not in the const constructor (Dart
  /// const-context can't access list length).
  const ColumnDefinition({required this.path, this.header});

  factory ColumnDefinition.fromJson(Map<String, Object?> json) {
    final pathRaw = json['path'];
    if (pathRaw is! List || pathRaw.isEmpty) {
      throw FormatException(
        'ColumnDefinition.path must be a non-empty list: $json',
      );
    }
    return ColumnDefinition(
      path: List<String>.unmodifiable(pathRaw.cast<String>()),
      header: json['header'] as String?,
    );
  }

  final List<String> path;
  final String? header;

  /// Display header — explicit [header] when set, otherwise the last path
  /// segment.
  String displayName() => header ?? path.last;

  Map<String, Object?> toJson() => {
    'path': path,
    if (header != null) 'header': header,
  };

  @override
  bool operator ==(Object other) {
    if (other is! ColumnDefinition) return false;
    if (other.header != header) return false;
    if (other.path.length != path.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (other.path[i] != path[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(header, Object.hashAll(path));
}

@immutable
class FilterDefinition {
  const FilterDefinition({
    required this.path,
    required this.op,
    required this.value,
  });

  factory FilterDefinition.fromJson(Map<String, Object?> json) {
    final pathRaw = json['path'];
    if (pathRaw is! List) {
      throw FormatException('FilterDefinition.path must be a list: $json');
    }
    final opName = json['op'] as String?;
    final op = FilterOp.values.firstWhere(
      (o) => o.name == opName,
      orElse: () => throw FormatException('Unknown filter op: $opName'),
    );
    return FilterDefinition(
      path: List<String>.unmodifiable(pathRaw.cast<String>()),
      op: op,
      value: (json['value'] as String?) ?? '',
    );
  }

  final List<String> path;
  final FilterOp op;
  final String value;

  Map<String, Object?> toJson() => {
    'path': path,
    'op': op.name,
    'value': value,
  };

  @override
  bool operator ==(Object other) =>
      other is FilterDefinition &&
      other.op == op &&
      other.value == value &&
      _listEq(other.path, path);

  @override
  int get hashCode => Object.hash(op, value, Object.hashAll(path));
}

enum FilterOp {
  /// Exact string match.
  eq,

  /// Substring match (case-insensitive).
  contains,
}

/// Direction an inclusion walks along an association. Forward = the
/// association is declared on the base class (base.assoc → child). Reverse
/// = the association is declared on the child class (child.assoc → base);
/// CIM uses this for "containment" patterns where Equipment carries the
/// EquipmentContainer pointer rather than EquipmentContainer carrying a
/// list.
enum InclusionDirection { forward, reverse }

/// 1-n composite inclusion: from a base element, expand up to [maxCount]
/// related children of [childClass] into repeated column groups, ordered by
/// [orderBy]. FR-2.7 .. FR-2.11.
@immutable
class CompositeInclusion {
  const CompositeInclusion({
    required this.association,
    required this.direction,
    required this.childClass,
    required this.orderBy,
    required this.maxCount,
    required this.attributes,
    this.descending = false,
    this.label,
  });

  factory CompositeInclusion.fromJson(Map<String, Object?> json) {
    final association = json['association'];
    final directionRaw = json['direction'];
    final childClass = json['childClass'];
    final orderBy = json['orderBy'];
    final maxCountRaw = json['maxCount'];
    final attributesRaw = json['attributes'];
    if (association is! String ||
        childClass is! String ||
        orderBy is! String ||
        maxCountRaw is! int ||
        attributesRaw is! List) {
      throw FormatException('Invalid CompositeInclusion: $json');
    }
    if (maxCountRaw <= 0) {
      throw FormatException('maxCount must be > 0: $maxCountRaw');
    }
    final direction = InclusionDirection.values.firstWhere(
      (d) => d.name == directionRaw,
      orElse: () =>
          throw FormatException('Unknown direction: $directionRaw'),
    );
    return CompositeInclusion(
      association: association,
      direction: direction,
      childClass: childClass,
      orderBy: orderBy,
      maxCount: maxCountRaw,
      attributes: List<String>.unmodifiable(attributesRaw.cast<String>()),
      descending: (json['descending'] as bool?) ?? false,
      label: json['label'] as String?,
    );
  }

  final String association;
  final InclusionDirection direction;
  final String childClass;
  final String orderBy;
  final int maxCount;
  final List<String> attributes;
  final bool descending;
  final String? label;

  Map<String, Object?> toJson() => {
    'association': association,
    'direction': direction.name,
    'childClass': childClass,
    'orderBy': orderBy,
    'maxCount': maxCount,
    'attributes': attributes,
    if (descending) 'descending': descending,
    if (label != null) 'label': label,
  };

  String displayLabel() => label ?? association;

  @override
  bool operator ==(Object other) =>
      other is CompositeInclusion &&
      other.association == association &&
      other.direction == direction &&
      other.childClass == childClass &&
      other.orderBy == orderBy &&
      other.maxCount == maxCount &&
      other.descending == descending &&
      other.label == label &&
      _listEq(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(
    association,
    direction,
    childClass,
    orderBy,
    maxCount,
    descending,
    label,
    Object.hashAll(attributes),
  );
}

@immutable
class SortDefinition {
  const SortDefinition({required this.path, required this.descending});

  factory SortDefinition.fromJson(Map<String, Object?> json) {
    final pathRaw = json['path'];
    if (pathRaw is! List) {
      throw FormatException('SortDefinition.path must be a list: $json');
    }
    return SortDefinition(
      path: List<String>.unmodifiable(pathRaw.cast<String>()),
      descending: (json['descending'] as bool?) ?? false,
    );
  }

  final List<String> path;
  final bool descending;

  Map<String, Object?> toJson() => {
    'path': path,
    'descending': descending,
  };

  @override
  bool operator ==(Object other) =>
      other is SortDefinition &&
      other.descending == descending &&
      _listEq(other.path, path);

  @override
  int get hashCode => Object.hash(descending, Object.hashAll(path));
}

/// A user-defined table view (TR-5.1). Serialized as JSON under
/// `.cimviews/<name>.json` so views travel in the repo alongside the model.
@immutable
class ViewDefinition {
  const ViewDefinition({
    required this.name,
    required this.baseClass,
    required this.columns,
    this.filters = const [],
    this.sort = const [],
    this.inclusions = const [],
  });

  factory ViewDefinition.fromJson(Map<String, Object?> json) {
    final formatVersion = json['formatVersion'];
    if (formatVersion is! int) {
      throw const FormatException(
        'ViewDefinition: missing or invalid formatVersion',
      );
    }
    if (formatVersion > 1) {
      throw FormatException(
        'ViewDefinition format $formatVersion is newer than supported (1)',
      );
    }
    final name = json['name'];
    final baseClass = json['baseClass'];
    if (name is! String || baseClass is! String) {
      throw FormatException(
        'ViewDefinition requires string name and baseClass: $json',
      );
    }
    final columnsRaw = json['columns'];
    if (columnsRaw is! List) {
      throw const FormatException('ViewDefinition.columns must be a list');
    }
    final filtersRaw = json['filters'] as List<Object?>?;
    final sortRaw = json['sort'] as List<Object?>?;
    final inclusionsRaw = json['inclusions'] as List<Object?>?;

    return ViewDefinition(
      name: name,
      baseClass: baseClass,
      columns: List.unmodifiable(
        columnsRaw.map(
          (c) => ColumnDefinition.fromJson(c! as Map<String, Object?>),
        ),
      ),
      filters: filtersRaw == null
          ? const []
          : List.unmodifiable(
              filtersRaw.map(
                (f) => FilterDefinition.fromJson(f! as Map<String, Object?>),
              ),
            ),
      sort: sortRaw == null
          ? const []
          : List.unmodifiable(
              sortRaw.map(
                (s) => SortDefinition.fromJson(s! as Map<String, Object?>),
              ),
            ),
      inclusions: inclusionsRaw == null
          ? const []
          : List.unmodifiable(
              inclusionsRaw.map(
                (i) => CompositeInclusion.fromJson(
                  i! as Map<String, Object?>,
                ),
              ),
            ),
    );
  }

  final String name;
  final String baseClass;
  final List<ColumnDefinition> columns;
  final List<FilterDefinition> filters;
  final List<SortDefinition> sort;
  final List<CompositeInclusion> inclusions;

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'name': name,
    'baseClass': baseClass,
    'columns': columns.map((c) => c.toJson()).toList(),
    if (filters.isNotEmpty)
      'filters': filters.map((f) => f.toJson()).toList(),
    if (sort.isNotEmpty) 'sort': sort.map((s) => s.toJson()).toList(),
    if (inclusions.isNotEmpty)
      'inclusions': inclusions.map((i) => i.toJson()).toList(),
  };

  ViewDefinition copyWith({
    String? name,
    String? baseClass,
    List<ColumnDefinition>? columns,
    List<FilterDefinition>? filters,
    List<SortDefinition>? sort,
    List<CompositeInclusion>? inclusions,
  }) {
    return ViewDefinition(
      name: name ?? this.name,
      baseClass: baseClass ?? this.baseClass,
      columns: columns ?? this.columns,
      filters: filters ?? this.filters,
      sort: sort ?? this.sort,
      inclusions: inclusions ?? this.inclusions,
    );
  }
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
