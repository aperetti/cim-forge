import 'dart:io';

import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
  });

  tearDown(() {
    db.close();
  });

  test('indexes elements, attributes, and associations from the sample graph',
      () {
    final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
    final graph = ObjectGraph.parse(src);

    final fileId = Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: null,
      graph: graph,
    );

    expect(fileId, isPositive);

    // Three top-level elements: _sub1, _line1, _line2.
    final elementCount = db.raw
        .select('SELECT COUNT(*) FROM elements')
        .first.values.first;
    expect(elementCount, 3);

    // _line1 has 3 scalar attributes (name, r, length).
    final line1Attrs = db.raw.select(
      'SELECT name, value FROM attributes WHERE element_id = ? ORDER BY name',
      ['_line1'],
    );
    // Stored under short names (FR-2.2 view columns reference attributes by
    // their bare names; the metamodel disambiguates inheritance).
    final names = line1Attrs.map((r) => r.values.first).toList();
    expect(names, ['length', 'name', 'r']);
  });

  test('indexes associations with correct src/dst ids', () {
    final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
    final graph = ObjectGraph.parse(src);
    Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: null,
      graph: graph,
    );

    final rows = db.raw.select(
      'SELECT src_element_id, name, dst_element_id FROM associations '
      'ORDER BY src_element_id',
    );
    expect(rows.length, 2);
    expect(rows.first.values, ['_line1', 'EquipmentContainer', '_sub1']);
  });

  test('reports progress at least at the end', () {
    final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
    final graph = ObjectGraph.parse(src);
    int? processedSeen;
    int? totalSeen;
    Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: null,
      graph: graph,
      onProgress: (p, t) {
        processedSeen = p;
        totalSeen = t;
      },
    );
    expect(processedSeen, graph.elementCount);
    expect(totalSeen, graph.elementCount);
  });

  test('re-indexing the same file path updates the existing files row', () {
    final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
    final graph = ObjectGraph.parse(src);

    final firstId = Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: 'sha-a',
      graph: graph,
    );

    // Clear element data and re-index — simulates a rebuild after edit.
    db.raw.execute('DELETE FROM elements');

    final secondId = Indexer(database: db).indexGraph(
      filePath: 'sample.xml',
      contentHash: 'sha-b',
      graph: graph,
    );

    expect(secondId, firstId);
    final hash = db.raw
        .select('SELECT content_hash FROM files WHERE id = ?', [firstId])
        .first
        .values
        .first;
    expect(hash, 'sha-b');
  });
}
