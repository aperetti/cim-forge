import 'dart:io';

import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/features/views/view_store.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const int _scaleElements = 50000;

void _synthesizeRows(AppDatabase db, {required int elements}) {
  final raw = db.raw
    ..execute('BEGIN')
    ..execute('''INSERT INTO files (id, path) VALUES (1, 'synthetic')''');

  final elementStmt = raw.prepare(
    'INSERT INTO elements (id, class, file_id, source_start, source_stop) '
    'VALUES (?, ?, 1, 0, 0)',
  );
  final attrStmt = raw.prepare(
    'INSERT INTO attributes (element_id, name, value, source_start, '
    'source_stop) VALUES (?, ?, ?, 0, 0)',
  );

  try {
    // One Substation as the container.
    elementStmt.execute(['_sub1', 'Substation']);
    attrStmt.execute(['_sub1', 'name', 'Substation A']);

    for (var i = 0; i < elements; i++) {
      final id = '_line$i';
      elementStmt.execute([id, 'ACLineSegment']);
      attrStmt
        ..execute([id, 'name', 'Feeder $i'])
        ..execute([id, 'length', (i % 5000).toString()]);
    }
    raw.execute('COMMIT');
  } on Object {
    raw.execute('ROLLBACK');
    rethrow;
  } finally {
    elementStmt.dispose();
    attrStmt.dispose();
  }
  // Refresh planner stats so QueryEngine queries pick the right indexes.
  raw.execute('ANALYZE');
}

void main() {
  late AppDatabase db;
  late QueryEngine engine;

  setUpAll(() {
    db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
    _synthesizeRows(db, elements: _scaleElements);
    final schemaSrc =
        File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync();
    engine = QueryEngine(metamodel: SchemaLoader.load(schemaSrc));
  });

  tearDownAll(() => db.close());

  group('M3 gate — TR-8 perf budgets at $_scaleElements elements', () {
    test('open view + first page < 3 s (cold) / much less (warm)', () {
      const view = ViewDefinition(
        name: 'AllLines',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['name']),
          ColumnDefinition(path: ['length']),
        ],
      );

      final sw = Stopwatch()..start();
      final count = engine.countMatching(db, view);
      final page = engine.execute(db, view, limit: 200, offset: 0);
      sw.stop();

      expect(count, _scaleElements);
      expect(page.length, 200);
      expect(
        sw.elapsedMilliseconds,
        lessThan(3000),
        reason: 'TR-8.2: cold open + first table render must be < 3 s '
            '($_scaleElements rows; was ${sw.elapsedMilliseconds} ms)',
      );
    });

    test('filtered query < 200 ms (TR-8.3)', () {
      const view = ViewDefinition(
        name: 'FilteredLines',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['name']),
          ColumnDefinition(path: ['length']),
        ],
        filters: [
          FilterDefinition(
            path: ['length'],
            op: FilterOp.eq,
            value: '1234',
          ),
        ],
      );

      // Warm pass first — TR-8.3 budgets the warm case.
      engine.execute(db, view, limit: 200, offset: 0);

      final sw = Stopwatch()..start();
      final page = engine.execute(db, view, limit: 200, offset: 0);
      sw.stop();

      expect(page, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(200),
        reason: 'TR-8.3: filter/sort/search must be < 200 ms '
            '(was ${sw.elapsedMilliseconds} ms)',
      );
    });

    test('sorted + filtered query < 200 ms', () {
      const view = ViewDefinition(
        name: 'SortedFilteredLines',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
        filters: [
          FilterDefinition(
            path: ['name'],
            op: FilterOp.contains,
            value: 'feeder 12',
          ),
        ],
        sort: [SortDefinition(path: ['name'], descending: false)],
      );

      engine.execute(db, view, limit: 200, offset: 0); // warm

      final sw = Stopwatch()..start();
      engine.execute(db, view, limit: 200, offset: 0);
      sw.stop();

      expect(
        sw.elapsedMilliseconds,
        lessThan(200),
        reason: 'TR-8.3: sorted + filtered query must be < 200 ms '
            '(was ${sw.elapsedMilliseconds} ms)',
      );
    });
  });

  group('M3 gate — view JSON round-trips through ViewStore', () {
    test('a saved-then-loaded view compiles to identical SQL '
        'and renders the same first page', () {
      final tempDir = Directory.systemTemp.createTempSync('cim_forge_m3_');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } on FileSystemException {/* tolerate Windows races */}
      });

      final store = ViewStore(
        viewsDirectory: Directory(p.join(tempDir.path, 'views')),
      );

      const original = ViewDefinition(
        name: 'Round-trip',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['name']),
          ColumnDefinition(path: ['length']),
        ],
        filters: [
          FilterDefinition(
            path: ['name'],
            op: FilterOp.contains,
            value: 'Feeder 1',
          ),
        ],
        sort: [SortDefinition(path: ['name'], descending: true)],
      );

      store.save(original);
      final reloaded = store.load('Round-trip');

      final originalSql = engine.compile(original);
      final reloadedSql = engine.compile(reloaded);

      expect(reloadedSql.sql, originalSql.sql);
      expect(reloadedSql.params, originalSql.params);

      final originalPage = engine.execute(db, original, limit: 50, offset: 0);
      final reloadedPage = engine.execute(db, reloaded, limit: 50, offset: 0);
      expect(reloadedPage.length, originalPage.length);
      for (var i = 0; i < originalPage.length; i++) {
        expect(reloadedPage[i].elementId, originalPage[i].elementId);
        expect(reloadedPage[i].values, originalPage[i].values);
      }
    });
  });
}
