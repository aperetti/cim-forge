import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:meta/meta.dart';

/// A row produced by a [ViewQuery]. [elementId] identifies the base element
/// — edits routed through the base columns land on that element. [values] is
/// in the same order as [ViewDefinition.columns]. [slots] is in the same
/// order as [ViewDefinition.inclusions] and is empty for non-composite views.
@immutable
class ViewRow {
  const ViewRow({
    required this.elementId,
    required this.values,
    this.slots = const [],
  });

  final String elementId;
  final List<String?> values;
  final List<InclusionSlotData> slots;
}

/// One inclusion's expanded children for a single row. [slots] is length
/// [CompositeInclusion.maxCount]; entries are null where no child is
/// present. [overflow] is true when the actual child count exceeds the
/// configured maximum (FR-2.11).
@immutable
class InclusionSlotData {
  const InclusionSlotData({required this.slots, required this.overflow});

  final List<ChildSlot?> slots;
  final bool overflow;
}

/// One occupied slot. [values] is in the same order as
/// [CompositeInclusion.attributes].
@immutable
class ChildSlot {
  const ChildSlot({required this.childId, required this.values});

  final String childId;
  final List<String?> values;
}

/// A compiled SQL plan derived from a [ViewDefinition]. The plan is
/// re-usable across calls; pagination is supplied at execution time.
@immutable
class ViewQuery {
  const ViewQuery({
    required this.sql,
    required this.params,
    required this.columnCount,
  });

  final String sql;
  final List<Object?> params;
  final int columnCount;
}

/// Translates view definitions into SQL against the M3 triple-store index.
/// The engine resolves path hops (association → next class) against the
/// [Metamodel] so we can validate that paths are well-formed for the base
/// class's inheritance chain.
class QueryEngine {
  QueryEngine({required this.metamodel});

  final Metamodel metamodel;

  ViewQuery compile(ViewDefinition view) {
    final builder = _QueryBuilder(metamodel: metamodel, view: view);
    return builder.build();
  }

  /// Compile and execute [view] against [db]. Returns [ViewRow]s in result
  /// order; pagination via [limit] / [offset]. Returns total row count via
  /// [countMatching] if needed for the grid.
  ///
  /// For composite views (`view.inclusions` non-empty), a follow-up query is
  /// issued per (row, inclusion) to fetch up to `maxCount + 1` ordered
  /// children. We accept the N+1 cost in this milestone; M9 may pre-compute
  /// slot assignments in a single window-function pass if profiling warrants.
  List<ViewRow> execute(
    AppDatabase db,
    ViewDefinition view, {
    required int limit,
    required int offset,
  }) {
    final query = compile(view);
    final sql = '${query.sql} LIMIT ? OFFSET ?';
    final params = [...query.params, limit, offset];
    final result = db.raw.select(sql, params);
    return [
      for (final row in result)
        ViewRow(
          elementId: row.values.first! as String,
          values: [
            for (var i = 1; i <= query.columnCount; i++)
              row.values[i] as String?,
          ],
          slots: [
            for (final inclusion in view.inclusions)
              _executeInclusion(
                db,
                inclusion,
                row.values.first! as String,
              ),
          ],
        ),
    ];
  }

  InclusionSlotData _executeInclusion(
    AppDatabase db,
    CompositeInclusion inclusion,
    String baseId,
  ) {
    final isReverse = inclusion.direction == InclusionDirection.reverse;
    final baseSide = isReverse ? 'dst_element_id' : 'src_element_id';
    final childSide = isReverse ? 'src_element_id' : 'dst_element_id';

    final selectParts = <String>[
      'a.$childSide AS child_id',
      'ob.value AS order_value',
    ];
    final joins = <String>[];
    for (var i = 0; i < inclusion.attributes.length; i++) {
      selectParts.add('attr_$i.value AS slot_attr_$i');
      joins.add(
        'LEFT JOIN attributes attr_$i '
        'ON attr_$i.element_id = a.$childSide '
        'AND attr_$i.name = ?',
      );
    }
    final sql =
        '''
SELECT ${selectParts.join(', ')}
FROM associations a
LEFT JOIN attributes ob
  ON ob.element_id = a.$childSide AND ob.name = ?
${joins.join('\n')}
WHERE a.$baseSide = ? AND a.name = ?
ORDER BY ob.value ${inclusion.descending ? 'DESC' : 'ASC'}, a.$childSide ASC
LIMIT ${inclusion.maxCount + 1}
''';

    // Param order mirrors the SQL text positionally: orderBy join, then
    // each attribute join in declaration order, then the WHERE base id,
    // then the WHERE association name.
    final params = <Object?>[
      inclusion.orderBy,
      ...inclusion.attributes,
      baseId,
      inclusion.association,
    ];

    final rows = db.raw.select(sql, params).toList();
    final overflow = rows.length > inclusion.maxCount;
    final slots = List<ChildSlot?>.filled(inclusion.maxCount, null);
    final taken = rows.length > inclusion.maxCount
        ? rows.take(inclusion.maxCount)
        : rows;
    var index = 0;
    for (final row in taken) {
      final values = <String?>[];
      for (var i = 0; i < inclusion.attributes.length; i++) {
        values.add(row['slot_attr_$i'] as String?);
      }
      slots[index] = ChildSlot(
        childId: row['child_id']! as String,
        values: values,
      );
      index++;
    }
    return InclusionSlotData(slots: slots, overflow: overflow);
  }

  /// Returns SQLite's EXPLAIN QUERY PLAN output for [view]. One row per
  /// plan step; the strings can be eyeballed to verify which indexes are
  /// being used. Pure diagnostic — does not execute the underlying query.
  List<String> explainQueryPlan(AppDatabase db, ViewDefinition view) {
    final query = compile(view);
    final rows = db.raw.select(
      'EXPLAIN QUERY PLAN ${query.sql}',
      query.params,
    );
    return [
      for (final row in rows)
        row.values.map((v) => v?.toString() ?? '').join(' | '),
    ];
  }

  /// Returns the total number of rows the view matches (no pagination).
  /// Used by the grid to know its rowCount.
  int countMatching(AppDatabase db, ViewDefinition view) {
    final query = compile(view);
    // Wrap the compiled SELECT in a COUNT subquery. Cheap: SQLite will plan
    // the same joins but only emit the row count.
    final sql = 'SELECT COUNT(*) FROM (${query.sql})';
    final result = db.raw.select(sql, query.params);
    return result.first.values.first! as int;
  }
}

class _QueryBuilder {
  _QueryBuilder({required this.metamodel, required this.view});

  final Metamodel metamodel;
  final ViewDefinition view;

  final StringBuffer _select = StringBuffer('SELECT e.id');
  final StringBuffer _from = StringBuffer('FROM elements e');
  final List<String> _wheres = [];
  // Params are collected per-clause and concatenated in SQL-text order
  // (FROM joins → WHERE → ORDER BY) when emitting, because SQLite resolves
  // `?` placeholders positionally against the rendered SQL.
  final List<Object?> _joinParams = [];
  final List<Object?> _whereParams = [];
  final List<String> _orderBy = [];
  int _aliasCounter = 0;

  // Cache joins so multiple references to the same path share an alias.
  final Map<String, String> _pathAlias = {};

  String _nextAlias() => 'j${_aliasCounter++}';

  ViewQuery build() {
    for (var i = 0; i < view.columns.length; i++) {
      final col = view.columns[i];
      final alias = _joinForAttributePath(col.path);
      _select.write(', $alias.value AS col_$i');
    }

    _wheres.add('e.class = ?');
    _whereParams.add(view.baseClass);

    for (final f in view.filters) {
      final alias = _joinForAttributePath(f.path);
      switch (f.op) {
        case FilterOp.eq:
          _wheres.add('$alias.value = ?');
          _whereParams.add(f.value);
        case FilterOp.contains:
          final ftsMatch = _tryBuildFtsMatch(f.value);
          if (ftsMatch != null && f.path.length == 1) {
            // Fast path (M9.1): narrow via the attributes_fts mirror.
            // Search semantics are token-based ("Feeder 12" → docs
            // containing both tokens); for arbitrary substring we'd need
            // a trigram tokenizer, which SQLite doesn't ship with.
            _wheres.add(
              'e.id IN (SELECT element_id FROM attributes_fts '
              'WHERE name = ? AND attributes_fts MATCH ?)',
            );
            _whereParams
              ..add(f.path.single)
              ..add(ftsMatch);
          } else {
            _wheres.add('LOWER($alias.value) LIKE ?');
            _whereParams.add('%${f.value.toLowerCase()}%');
          }
      }
    }

    for (final s in view.sort) {
      final alias = _joinForAttributePath(s.path);
      _orderBy.add('$alias.value ${s.descending ? "DESC" : "ASC"}');
    }
    // Stable ordering — guarantees pagination is deterministic.
    _orderBy.add('e.id ASC');

    final sql = StringBuffer()
      ..write(_select)
      ..write(' ')
      ..write(_from)
      ..write(' WHERE ')
      ..writeAll(_wheres, ' AND ')
      ..write(' ORDER BY ')
      ..writeAll(_orderBy, ', ');

    return ViewQuery(
      sql: sql.toString(),
      params: List.unmodifiable([..._joinParams, ..._whereParams]),
      columnCount: view.columns.length,
    );
  }

  /// Walk [path] from the base element, joining one association table per
  /// hop. The terminal segment is the attribute. Returns the alias of the
  /// attributes table for that terminal attribute.
  String _joinForAttributePath(List<String> path) {
    if (path.isEmpty) {
      throw ArgumentError('view path cannot be empty');
    }
    final cacheKey = path.join('.');
    final cached = _pathAlias[cacheKey];
    if (cached != null) return cached;

    var currentElementAlias = 'e';
    var currentClass = view.baseClass;

    // All but the last segment are association hops.
    for (var i = 0; i < path.length - 1; i++) {
      final hop = path[i];
      final assoc = _resolveAssociation(currentClass, hop);
      final assocAlias = _nextAlias();
      _from.write(
        ' INNER JOIN associations $assocAlias '
        'ON $assocAlias.src_element_id = $currentElementAlias.id '
        'AND $assocAlias.name = ?',
      );
      _joinParams.add(hop);
      // Then join into elements via dst — we need its id as the next "from".
      final elemAlias = _nextAlias();
      _from.write(
        ' INNER JOIN elements $elemAlias '
        'ON $elemAlias.id = $assocAlias.dst_element_id',
      );
      currentElementAlias = elemAlias;
      currentClass = assoc.targetClass;
    }

    // Terminal: join attributes table for the final attribute name.
    final attrName = path.last;
    // Validate: the metamodel should declare this attribute on currentClass.
    final legal = metamodel.attributesOf(currentClass).any(
      (a) => a.name == attrName,
    );
    if (!legal) {
      throw ArgumentError(
        'view column references unknown attribute '
        '$currentClass.$attrName (path: ${path.join(".")})',
      );
    }
    final attrAlias = _nextAlias();
    _from.write(
      ' LEFT JOIN attributes $attrAlias '
      'ON $attrAlias.element_id = $currentElementAlias.id '
      'AND $attrAlias.name = ?',
    );
    _joinParams.add(attrName);

    _pathAlias[cacheKey] = attrAlias;
    return attrAlias;
  }

  /// Builds an FTS5 MATCH expression from user-typed search input. Returns
  /// null when the input has no FTS5-safe tokens (special chars, empty,
  /// quoting); the caller falls back to LIKE in that case.
  ///
  /// Tokens are joined with spaces, producing FTS5's implicit AND search
  /// (all tokens must appear in the same row). The trailing token gets a
  /// `*` so "Feed" matches "Feeder" — type-ahead-friendly.
  String? _tryBuildFtsMatch(String userInput) {
    final tokens = userInput
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && _ftsSafeToken.hasMatch(t))
        .toList();
    if (tokens.isEmpty) return null;
    // Prefix-match the trailing token. The earlier tokens are required to
    // appear as-is, which is what users typing "Feeder 12" expect.
    final last = tokens.removeLast();
    tokens.add('$last*');
    return tokens.join(' ');
  }

  static final RegExp _ftsSafeToken = RegExp(r'^[A-Za-z0-9_]+$');

  CimAssociation _resolveAssociation(String fromClass, String name) {
    final assocs = metamodel.associationsOf(fromClass);
    for (final a in assocs) {
      if (a.name == name) return a;
    }
    throw ArgumentError(
      'view path references unknown association $fromClass.$name',
    );
  }
}
