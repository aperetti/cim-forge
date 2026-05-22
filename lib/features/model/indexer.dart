import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/shared/storage/database.dart';

/// Reports incremental progress while indexing — emitted on the same isolate
/// the indexer runs on. The UI bridges this to its state.
typedef IndexProgressSink = void Function(int processed, int total);

/// Indexes an [ObjectGraph] into the triple-store tables of the supplied
/// database. Inserts the file row, then bulk-inserts elements, attributes,
/// and associations in a single transaction for speed.
///
/// Returns the `file_id` assigned to the input file path — the caller will
/// use it for later incremental updates and for reverse lookups (FR-4.5:
/// which file does this element come from?).
class Indexer {
  Indexer({required this.database});

  final AppDatabase database;

  int indexGraph({
    required String filePath,
    required String? contentHash,
    required ObjectGraph graph,
    IndexProgressSink? onProgress,
  }) {
    final db = database.raw;

    final fileId = _upsertFile(filePath, contentHash);
    // Idempotency: clear any rows previously indexed for this file_id so
    // re-indexing replaces them. ON DELETE CASCADE handles attributes and
    // associations; the M9.1 FTS5 triggers clean the mirror.
    db.execute('DELETE FROM elements WHERE file_id = ?', [fileId]);
    final elementStmt = db.prepare(
      'INSERT INTO elements '
      '(id, class, file_id, source_start, source_stop) VALUES (?, ?, ?, ?, ?)',
    );
    final attrStmt = db.prepare(
      'INSERT INTO attributes '
      '(element_id, name, value, source_start, source_stop) '
      'VALUES (?, ?, ?, ?, ?)',
    );
    final assocStmt = db.prepare(
      'INSERT INTO associations '
      '(src_element_id, name, dst_element_id, source_start, source_stop) '
      'VALUES (?, ?, ?, ?, ?)',
    );

    final elementCount = graph.elementCount;
    var processed = 0;
    db.execute('BEGIN');
    try {
      for (final el in graph.elements) {
        elementStmt.execute([
          el.id,
          el.className,
          fileId,
          el.headerSpan.start,
          el.closingSpan?.stop ?? el.headerSpan.stop,
        ]);
        for (final a in el.attributes) {
          attrStmt.execute([
            el.id,
            a.shortName,
            a.value,
            a.textSpan.start,
            a.textSpan.stop,
          ]);
        }
        for (final a in el.associations) {
          assocStmt.execute([
            el.id,
            a.shortName,
            a.targetId,
            a.targetSpan.start,
            a.targetSpan.stop,
          ]);
        }
        processed++;
        if (onProgress != null && processed % 1024 == 0) {
          onProgress(processed, elementCount);
        }
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      elementStmt.dispose();
      attrStmt.dispose();
      assocStmt.dispose();
    }

    onProgress?.call(processed, elementCount);
    return fileId;
  }

  int _upsertFile(String path, String? hash) {
    final db = database.raw;
    final existing = db.select(
      'SELECT id FROM files WHERE path = ?',
      [path],
    );
    if (existing.isNotEmpty) {
      final id = existing.first.values.first! as int;
      db.execute('UPDATE files SET content_hash = ? WHERE id = ?', [hash, id]);
      return id;
    }
    db.execute('INSERT INTO files (path, content_hash) VALUES (?, ?)', [
      path,
      hash,
    ]);
    return db.select('SELECT last_insert_rowid()').first.values.first! as int;
  }
}
