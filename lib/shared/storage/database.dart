import 'package:sqlite3/sqlite3.dart';
// ignore: unused_import — registers the bundled sqlite3 native library.
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

class Migration {
  const Migration({required this.version, required this.up});

  final int version;
  final void Function(Database db) up;
}

class AppDatabase {
  AppDatabase._(this._db);

  factory AppDatabase.open(
    String path, {
    required List<Migration> migrations,
  }) {
    final db = sqlite3.open(path);
    _configureConnection(db);
    _applyMigrations(db, migrations);
    return AppDatabase._(db);
  }

  factory AppDatabase.openInMemory({required List<Migration> migrations}) {
    final db = sqlite3.openInMemory();
    _configureConnection(db);
    _applyMigrations(db, migrations);
    return AppDatabase._(db);
  }

  static void _configureConnection(Database db) {
    // Foreign keys are off by default in SQLite (legacy behavior). Without
    // this, ON DELETE CASCADE doesn't fire and we'd accumulate orphans on
    // re-index.
    db.execute('PRAGMA foreign_keys = ON');
  }

  final Database _db;

  Database get raw => _db;

  static void _applyMigrations(Database db, List<Migration> migrations) {
    final sorted = [...migrations]
      ..sort((a, b) => a.version.compareTo(b.version));
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].version != i + 1) {
        throw StateError(
          'Migrations must be contiguous starting at 1; '
          'found version ${sorted[i].version} at index $i',
        );
      }
    }

    final currentVersion = _readUserVersion(db);
    for (final migration in sorted) {
      if (migration.version <= currentVersion) continue;
      db.execute('BEGIN');
      try {
        migration.up(db);
        db
          ..execute('PRAGMA user_version = ${migration.version}')
          ..execute('COMMIT');
      } on Object {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  static int _readUserVersion(Database db) {
    final value = db.select('PRAGMA user_version').first.values.first;
    if (value is int) return value;
    throw StateError('PRAGMA user_version returned non-integer: $value');
  }

  int get schemaVersion => _readUserVersion(_db);

  void close() => _db.dispose();
}
