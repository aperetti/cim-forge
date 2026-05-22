import 'dart:io';

import 'package:cim_forge/features/model/background_indexer.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String dbPath;
  late String sourcePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cim_forge_bg_idx_');
    dbPath = p.join(tempDir.path, 'index.sqlite3');
    sourcePath = p.join(tempDir.path, 'sample.xml');
    File(sourcePath).writeAsStringSync(
      File('test/fixtures/cim/sample.xml').readAsStringSync(),
    );

    // Initialize the schema (the worker assumes the file exists with
    // migrations applied — matches the real Project.create path).
    AppDatabase.open(dbPath, migrations: cimIndexMigrations).close();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold .sqlite3-shm/-wal handles briefly.
    }
  });

  test('streams progress and produces a result the synchronous Indexer '
      'would have produced', () async {
    final progressEvents = <(int, int)>[];

    final result = await BackgroundIndexer.run(
      sourcePath: sourcePath,
      dbPath: dbPath,
      onProgress: (p, t) => progressEvents.add((p, t)),
    );

    expect(result.fileId, isPositive);
    expect(result.elementCount, 3);
    expect(result.totalDuration, isNotNull);

    // Final progress event is always (count, count).
    expect(progressEvents.last.$1, result.elementCount);
    expect(progressEvents.last.$2, result.elementCount);

    // Verify the SQLite rows the worker wrote are visible to a fresh
    // main-isolate connection.
    final db = AppDatabase.open(dbPath, migrations: cimIndexMigrations);
    addTearDown(db.close);

    final elements = db.raw
        .select('SELECT id, class FROM elements ORDER BY id')
        .map((r) => (r['id']! as String, r['class']! as String))
        .toList();
    expect(elements, [
      ('_line1', 'ACLineSegment'),
      ('_line2', 'ACLineSegment'),
      ('_sub1', 'Substation'),
    ]);
  });

  test('worker writes the same rows as a sync Indexer would have', () async {
    await BackgroundIndexer.run(
      sourcePath: sourcePath,
      dbPath: dbPath,
    );

    // Build a parallel reference via the synchronous Indexer into a fresh
    // database, then compare row sets.
    final referenceDb =
        AppDatabase.openInMemory(migrations: cimIndexMigrations);
    addTearDown(referenceDb.close);
    Indexer(database: referenceDb).indexGraph(
      filePath: sourcePath,
      contentHash: null,
      graph: ObjectGraph.parse(File(sourcePath).readAsStringSync()),
    );

    final bg = AppDatabase.open(dbPath, migrations: cimIndexMigrations);
    addTearDown(bg.close);

    final bgRows = bg.raw
        .select('SELECT element_id, name, value FROM attributes '
            'ORDER BY element_id, name')
        .map((r) => r.values.join('|'))
        .toList();
    final refRows = referenceDb.raw
        .select('SELECT element_id, name, value FROM attributes '
            'ORDER BY element_id, name')
        .map((r) => r.values.join('|'))
        .toList();
    expect(bgRows, refRows);
  });
}
