import 'dart:io';

import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/query_grid_source.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late QueryEngine engine;

  setUp(() {
    db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
    final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
    Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: null,
      graph: ObjectGraph.parse(src),
    );
    final schemaSrc =
        File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync();
    engine = QueryEngine(metamodel: SchemaLoader.load(schemaSrc));
  });

  tearDown(() {
    db.close();
  });

  test('reports correct row + column counts at construction', () {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'V',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['name']),
          ColumnDefinition(path: ['length']),
        ],
      ),
    );
    addTearDown(source.dispose);
    expect(source.rowCount, 2);
    expect(source.columnCount, 2);
    expect(source.columnAt(0).header, 'name');
    expect(source.columnAt(1).header, 'length');
  });

  test('resolves cells after the async window fetch settles', () async {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'V',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
      ),
    );
    addTearDown(source.dispose);

    // Pre-window-fetch reads return the placeholder.
    final pre = source.cellAt(0, 0);
    expect(pre, isNot('Feeder 12'));

    // Let the scheduled window fetch run.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(source.cellAt(0, 0), 'Feeder 12');
    expect(source.cellAt(1, 0), 'Feeder 13');
  });

  test('elementIdAt returns the row identity once resolved', () async {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'V',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
      ),
    );
    addTearDown(source.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(source.elementIdAt(0), '_line1');
    expect(source.elementIdAt(1), '_line2');
  });

  test('setView swaps definition and refreshes row count', () async {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'AllLines',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
      ),
    );
    addTearDown(source.dispose);
    expect(source.rowCount, 2);

    source.setView(
      const ViewDefinition(
        name: 'AllSubs',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
      ),
    );
    expect(source.rowCount, 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(source.cellAt(0, 0), 'Substation A');
  });
}
