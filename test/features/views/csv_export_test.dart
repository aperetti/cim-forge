import 'dart:io';

import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/csv_export.dart';
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
    Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: null,
      graph: ObjectGraph.parse(src),
    );
    engine = QueryEngine(
      metamodel: SchemaLoader.load(
        File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync(),
      ),
    );
  });

  tearDown(() => db.close());

  test('exports a simple view with header + two data rows', () {
    const view = ViewDefinition(
      name: 'Feeders',
      baseClass: 'ACLineSegment',
      columns: [
        ColumnDefinition(path: ['name']),
        ColumnDefinition(path: ['length']),
      ],
    );
    final csv = exportViewAsCsv(db, engine, view);
    final lines = csv.trim().split(RegExp(r'\r?\n'));
    expect(lines.first, 'name,length');
    expect(lines, contains('Feeder 12,1234.5'));
    expect(lines, contains('Feeder 13,987.0'));
  });

  test('quotes fields containing commas, quotes, or newlines', () {
    // Insert an extra element with a value that needs CSV escaping — the
    // fixture's file_id 1 already exists from setUp's Indexer call.
    db.raw.execute(
      'INSERT INTO elements (id, class, file_id, source_start, source_stop) '
      "VALUES ('_x', 'ACLineSegment', 1, 0, 0)",
    );
    db.raw.execute(
      'INSERT INTO attributes '
      '(element_id, name, value, source_start, source_stop) '
      'VALUES (?, ?, ?, 0, 0)',
      ['_x', 'name', 'A, B "quoted" C'],
    );

    const view = ViewDefinition(
      name: 'Quoted',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
    );
    final csv = exportViewAsCsv(db, engine, view);
    expect(csv, contains('"A, B ""quoted"" C"'));
  });
}
