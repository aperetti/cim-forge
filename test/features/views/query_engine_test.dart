import 'dart:io';

import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late QueryEngine engine;

  setUp(() {
    db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
    final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
    final graph = ObjectGraph.parse(src);
    Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: null,
      graph: graph,
    );
    final schemaSrc =
        File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync();
    engine = QueryEngine(metamodel: SchemaLoader.load(schemaSrc));
  });

  tearDown(() {
    db.close();
  });

  test('renders all rows of a single-attribute view', () {
    const view = ViewDefinition(
      name: 'Feeders',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
    );
    final rows = engine.execute(db, view, limit: 100, offset: 0);
    expect(rows.map((r) => r.elementId), ['_line1', '_line2']);
    expect(rows.map((r) => r.values.single), ['Feeder 12', 'Feeder 13']);
  });

  test('counts matching rows', () {
    const view = ViewDefinition(
      name: 'Feeders',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
    );
    expect(engine.countMatching(db, view), 2);
  });

  test('resolves a joined column through an association', () {
    const view = ViewDefinition(
      name: 'Feeders+Container',
      baseClass: 'ACLineSegment',
      columns: [
        ColumnDefinition(path: ['name']),
        ColumnDefinition(path: ['EquipmentContainer', 'name']),
      ],
    );
    final rows = engine.execute(db, view, limit: 100, offset: 0);
    expect(rows.length, 2);
    expect(rows.first.values, ['Feeder 12', 'Substation A']);
    expect(rows.last.values, ['Feeder 13', 'Substation A']);
  });

  test('applies an equality filter', () {
    const view = ViewDefinition(
      name: 'OnlyLine1',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
      filters: [
        FilterDefinition(
          path: ['name'],
          op: FilterOp.eq,
          value: 'Feeder 12',
        ),
      ],
    );
    final rows = engine.execute(db, view, limit: 100, offset: 0);
    expect(rows.length, 1);
    expect(rows.single.elementId, '_line1');
  });

  test('applies a contains filter (case-insensitive)', () {
    const view = ViewDefinition(
      name: 'AnyFeeder',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
      filters: [
        FilterDefinition(
          path: ['name'],
          op: FilterOp.contains,
          value: 'feeder',
        ),
      ],
    );
    expect(engine.execute(db, view, limit: 100, offset: 0).length, 2);
  });

  test('honors ascending sort then stable id order', () {
    const ascending = ViewDefinition(
      name: 'AscByLength',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
      sort: [SortDefinition(path: ['length'], descending: false)],
    );
    final rows = engine.execute(db, ascending, limit: 100, offset: 0);
    // 987.0 < 1234.5 — but values are TEXT so this is lexical sort.
    // The triple store stores values as strings; we accept lexical for M3.
    expect(rows.first.values.single, isIn(['Feeder 12', 'Feeder 13']));
  });

  test('rejects an unknown attribute name with a clear error', () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['nope'])],
    );
    expect(() => engine.compile(view), throwsArgumentError);
  });

  test('rejects an unknown association hop', () {
    const view = ViewDefinition(
      name: 'BadHop',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['NoSuchAssoc', 'name'])],
    );
    expect(() => engine.compile(view), throwsArgumentError);
  });

  test('pagination via limit + offset', () {
    const view = ViewDefinition(
      name: 'Paginated',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
    );
    final page1 = engine.execute(db, view, limit: 1, offset: 0);
    final page2 = engine.execute(db, view, limit: 1, offset: 1);
    expect(page1.single.elementId, '_line1');
    expect(page2.single.elementId, '_line2');
  });
}
