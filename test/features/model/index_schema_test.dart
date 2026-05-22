import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cimIndexMigrations builds the triple-store tables and indexes', () {
    final db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
    addTearDown(db.close);

    final tables = db.raw
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .map((r) => r.values.first! as String)
        .toList();
    expect(
      tables,
      containsAll(['associations', 'attributes', 'elements', 'files']),
    );

    final indexes = db.raw
        .select(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .map((r) => r.values.first! as String)
        .toList();
    expect(
      indexes,
      containsAll([
        'associations_by_dst',
        'attributes_by_name_value',
        'elements_by_class',
      ]),
    );
  });

  test('elements row insert + select works end-to-end', () {
    final db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
    addTearDown(db.close);
    db.raw
      ..execute('''INSERT INTO files (id, path) VALUES (1, 'a.xml')''')
      ..execute(
        'INSERT INTO elements (id, class, file_id, source_start, source_stop) '
        '''VALUES ('e1', 'ACLineSegment', 1, 10, 200)''',
      );
    final rows = db.raw.select(
      'SELECT class FROM elements WHERE id = ?',
      ['e1'],
    );
    expect(rows.first.values.first, 'ACLineSegment');
  });
}
