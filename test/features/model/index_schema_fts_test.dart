import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
    db.raw
      ..execute('''INSERT INTO files (id, path) VALUES (1, 'inline')''')
      ..execute(
        'INSERT INTO elements (id, class, file_id, source_start, '
        "source_stop) VALUES ('_a', 'C', 1, 0, 0)",
      )
      ..execute(
        'INSERT INTO elements (id, class, file_id, source_start, '
        "source_stop) VALUES ('_b', 'C', 1, 0, 0)",
      );
  });

  tearDown(() => db.close());

  test('attributes_fts virtual table is created by v2', () {
    final tables = db.raw
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name = 'attributes_fts'",
        )
        .map((r) => r.values.first! as String)
        .toList();
    expect(tables, ['attributes_fts']);
  });

  test('insert trigger propagates to FTS5 mirror', () {
    db.raw.execute(
      'INSERT INTO attributes (element_id, name, value, source_start, '
      "source_stop) VALUES ('_a', 'name', 'Feeder 12', 0, 0)",
    );
    final rows = db.raw.select(
      'SELECT element_id, name, value FROM attributes_fts '
      "WHERE attributes_fts MATCH 'Feeder'",
    );
    expect(rows.length, 1);
    expect(rows.first['element_id'], '_a');
    expect(rows.first['name'], 'name');
    expect(rows.first['value'], 'Feeder 12');
  });

  test('update trigger refreshes the FTS5 mirror', () {
    db.raw
      ..execute(
        'INSERT INTO attributes (element_id, name, value, source_start, '
        "source_stop) VALUES ('_a', 'name', 'Old Name', 0, 0)",
      )
      ..execute(
        "UPDATE attributes SET value = 'New Name' "
        "WHERE element_id = '_a' AND name = 'name'",
      );

    final oldHits = db.raw.select(
      "SELECT value FROM attributes_fts WHERE attributes_fts MATCH 'Old'",
    );
    final newHits = db.raw.select(
      "SELECT value FROM attributes_fts WHERE attributes_fts MATCH 'New'",
    );
    expect(oldHits, isEmpty);
    expect(newHits.length, 1);
    expect(newHits.first['value'], 'New Name');
  });

  test('delete trigger removes the FTS5 row', () {
    db.raw
      ..execute(
        'INSERT INTO attributes (element_id, name, value, source_start, '
        "source_stop) VALUES ('_a', 'name', 'doomed', 0, 0)",
      )
      ..execute(
        "DELETE FROM attributes WHERE element_id = '_a' AND name = 'name'",
      );
    final hits = db.raw.select(
      "SELECT value FROM attributes_fts WHERE attributes_fts MATCH 'doomed'",
    );
    expect(hits, isEmpty);
  });

  test('cascade delete via elements.id removes attribute and FTS5 row', () {
    db.raw
      ..execute(
        'INSERT INTO attributes (element_id, name, value, source_start, '
        "source_stop) VALUES ('_a', 'name', 'cascade me', 0, 0)",
      )
      ..execute("DELETE FROM elements WHERE id = '_a'");
    // The element row is gone; the attribute row should be too (FK CASCADE).
    final attrRows = db.raw.select(
      "SELECT 1 FROM attributes WHERE element_id = '_a'",
    );
    expect(attrRows, isEmpty);
    final ftsRows = db.raw.select(
      "SELECT 1 FROM attributes_fts WHERE attributes_fts MATCH 'cascade'",
    );
    expect(ftsRows, isEmpty);
  });

  test('FTS5 backfill picks up rows inserted before migration v2 ran',
      () {
    // Simulate "v1 already applied, now applying v2" by opening a fresh DB
    // at v1, inserting attributes, then running the v2 migration manually.
    final v1Only = AppDatabase.openInMemory(
      migrations: [cimIndexMigrations.first],
    );
    addTearDown(v1Only.close);
    v1Only.raw
      ..execute('''INSERT INTO files (id, path) VALUES (1, 'x')''')
      ..execute(
        'INSERT INTO elements (id, class, file_id, source_start, '
        "source_stop) VALUES ('_x', 'C', 1, 0, 0)",
      )
      ..execute(
        'INSERT INTO attributes (element_id, name, value, source_start, '
        "source_stop) VALUES ('_x', 'name', 'pre-v2 row', 0, 0)",
      );

    // Now apply v2 manually using the same callback list.
    final v2 = cimIndexMigrations.where((m) => m.version == 2).first;
    v2.up(v1Only.raw);

    final hits = v1Only.raw.select(
      "SELECT value FROM attributes_fts WHERE attributes_fts MATCH 'row'",
    );
    expect(hits.length, 1);
    expect(hits.first['value'], 'pre-v2 row');
  });
}
