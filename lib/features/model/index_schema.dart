import 'package:cim_forge/shared/storage/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Migrations for the triple-store index that backs CIM Forge view queries
/// (TR-4.2). The schema is profile-agnostic (FR-1.2): no class names or
/// attribute names are part of the SQL surface — every class becomes a row
/// in `elements.class`, every attribute a row in `attributes`, every
/// association a row in `associations`. Per-class materialized views are an
/// optimization we add later if profiling demands it.
///
/// Indexes prioritize the two read paths views actually drive:
///   - "all elements of class X" → `elements(class)`
///   - "value of attribute N on element E" → `attributes(element_id, name)`
///   - "association walks" → `associations(src_element_id, name)` and
///     `associations(dst_element_id, name)` (for back-edges).
const List<Migration> cimIndexMigrations = [
  Migration(version: 1, up: _v1),
  Migration(version: 2, up: _v2),
];

void _v1(Database db) {
  db
    ..execute('''
      CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        content_hash TEXT
      )
    ''')
    ..execute('''
      CREATE TABLE elements (
        id TEXT PRIMARY KEY,
        class TEXT NOT NULL,
        file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
        source_start INTEGER NOT NULL,
        source_stop INTEGER NOT NULL
      )
    ''')
    ..execute('CREATE INDEX elements_by_class ON elements(class)')
    ..execute('''
      CREATE TABLE attributes (
        element_id TEXT NOT NULL REFERENCES elements(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        value TEXT NOT NULL,
        source_start INTEGER NOT NULL,
        source_stop INTEGER NOT NULL,
        PRIMARY KEY (element_id, name)
      ) WITHOUT ROWID
    ''')
    ..execute(
      'CREATE INDEX attributes_by_name_value ON attributes(name, value)',
    )
    ..execute('''
      CREATE TABLE associations (
        src_element_id TEXT NOT NULL
          REFERENCES elements(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        dst_element_id TEXT NOT NULL,
        source_start INTEGER NOT NULL,
        source_stop INTEGER NOT NULL,
        PRIMARY KEY (src_element_id, name, dst_element_id)
      ) WITHOUT ROWID
    ''')
    ..execute(
      'CREATE INDEX associations_by_dst ON associations(dst_element_id, name)',
    );
}

/// v2 — FTS5 mirror of attribute values for fast substring search
/// (M9.1). The mirror is kept in sync via triggers; we never write to it
/// directly. Token-based search ("Feeder 12" → docs containing both tokens)
/// is what user-typed search boxes actually want; arbitrary substring
/// (e.g. "eder 12") still falls back to LIKE in the query engine.
void _v2(Database db) {
  db
    ..execute('''
      CREATE VIRTUAL TABLE attributes_fts USING fts5(
        value,
        element_id UNINDEXED,
        name UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''')
    // Backfill — runs once when migrating an existing project. New rows
    // arrive via the AFTER INSERT trigger below.
    ..execute('''
      INSERT INTO attributes_fts (value, element_id, name)
      SELECT value, element_id, name FROM attributes
    ''')
    ..execute('''
      CREATE TRIGGER attributes_fts_after_insert
      AFTER INSERT ON attributes BEGIN
        INSERT INTO attributes_fts (value, element_id, name)
        VALUES (new.value, new.element_id, new.name);
      END
    ''')
    ..execute('''
      CREATE TRIGGER attributes_fts_after_update
      AFTER UPDATE OF value ON attributes BEGIN
        DELETE FROM attributes_fts
        WHERE element_id = old.element_id AND name = old.name;
        INSERT INTO attributes_fts (value, element_id, name)
        VALUES (new.value, new.element_id, new.name);
      END
    ''')
    ..execute('''
      CREATE TRIGGER attributes_fts_after_delete
      AFTER DELETE ON attributes BEGIN
        DELETE FROM attributes_fts
        WHERE element_id = old.element_id AND name = old.name;
      END
    ''');
}
