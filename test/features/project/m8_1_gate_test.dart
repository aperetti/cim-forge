import 'dart:io';

import 'package:cim_forge/features/model/background_indexer.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/project/project.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:cim_forge/shared/telemetry/spans.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('M8.1 gate — Project DB release / reopen handoff', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cim_forge_m81_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows .sqlite3-shm handle race.
      }
    });

    test('release → reopen → DB round-trips a query', () {
      final project =
          Project.create(tempDir, telemetry: Telemetry(sink: (_) {}))
        ..database.raw.execute(
          'CREATE TABLE round_trip (k TEXT PRIMARY KEY, v TEXT)',
        )
        ..database.raw.execute("INSERT INTO round_trip VALUES ('a', 'one')");
      addTearDown(project.close);

      project.releaseDatabase();
      expect(project.isDatabaseReleased, isTrue);
      expect(() => project.database, throwsStateError);

      project.reopenDatabase();
      expect(project.isDatabaseReleased, isFalse);
      final row = project.database.raw.select(
        "SELECT v FROM round_trip WHERE k = 'a'",
      );
      expect(row.first.values.first, 'one');
    });

    test('background indexer run between release/reopen produces visible rows',
        () async {
      final project =
          Project.create(tempDir, telemetry: Telemetry(sink: (_) {}));
      addTearDown(project.close);

      final modelPath = p.join(tempDir.path, 'sample.xml');
      File(modelPath).writeAsStringSync(
        File('test/fixtures/cim/sample.xml').readAsStringSync(),
      );

      project.releaseDatabase();
      late BackgroundIndexResult result;
      try {
        result = await BackgroundIndexer.run(
          sourcePath: modelPath,
          dbPath: project.layout.indexPath,
        );
      } finally {
        project.reopenDatabase();
      }
      expect(result.fileId, isPositive);
      expect(result.elementCount, 3);

      // The main isolate's reopened handle sees the worker's writes.
      final rows = project.database.raw
          .select('SELECT id FROM elements ORDER BY id')
          .map((r) => r.values.first! as String)
          .toList();
      expect(rows, ['_line1', '_line2', '_sub1']);
    });
  });

  group('M8.1 gate — Indexer idempotency', () {
    test('re-indexing the same file replaces rows rather than duplicating',
        () {
      final db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
      addTearDown(db.close);
      final source = File('test/fixtures/cim/sample.xml').readAsStringSync();
      final indexer = Indexer(database: db);

      final firstFileId = indexer.indexGraph(
        filePath: 'sample.xml',
        contentHash: null,
        graph: ObjectGraph.parse(source),
      );
      final firstCount = db.raw
          .select('SELECT COUNT(*) FROM elements')
          .first
          .values
          .first;

      // Second indexing of the same source — no duplicate-key errors.
      final secondFileId = indexer.indexGraph(
        filePath: 'sample.xml',
        contentHash: null,
        graph: ObjectGraph.parse(source),
      );
      final secondCount = db.raw
          .select('SELECT COUNT(*) FROM elements')
          .first
          .values
          .first;

      expect(secondFileId, firstFileId, reason: 'files row is reused');
      expect(secondCount, firstCount,
          reason: 're-index is idempotent — same row count');
    });

    test('re-indexing after an external mutation rebuilds the prior content',
        () {
      final db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
      addTearDown(db.close);
      final source = File('test/fixtures/cim/sample.xml').readAsStringSync();
      final indexer = Indexer(database: db)
        ..indexGraph(
          filePath: 'sample.xml',
          contentHash: null,
          graph: ObjectGraph.parse(source),
        );

      // Simulate the index drifting from the graph (e.g. an earlier crash).
      db.raw.execute("DELETE FROM elements WHERE id = '_line1'");
      expect(
        db.raw
            .select("SELECT 1 FROM elements WHERE id = '_line1'")
            .isEmpty,
        isTrue,
      );

      indexer.indexGraph(
        filePath: 'sample.xml',
        contentHash: null,
        graph: ObjectGraph.parse(source),
      );

      // _line1 is back, source-of-truth from the parsed graph.
      expect(
        db.raw
            .select("SELECT 1 FROM elements WHERE id = '_line1'")
            .isNotEmpty,
        isTrue,
      );
    });
  });
}
