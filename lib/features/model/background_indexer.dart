import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:meta/meta.dart';

@immutable
class BackgroundIndexResult {
  const BackgroundIndexResult({
    required this.fileId,
    required this.elementCount,
    required this.totalDuration,
  });
  final int fileId;
  final int elementCount;
  final Duration totalDuration;
}

/// Runs the [Indexer] on a worker isolate so the UI thread stays responsive
/// while a large model loads (TR-4.5, FR-8.2).
///
/// **Calling contract:** the main isolate must release its handle to the
/// SQLite file before invoking [run] and reopen it afterwards. SQLite's WAL
/// mode tolerates concurrent readers and one writer, but the simpler
/// invariant — exclusive access during a bulk insert — is what this class
/// assumes.
class BackgroundIndexer {
  /// Indexes the model at [sourcePath] into the SQLite file at [dbPath].
  /// Streams progress via [onProgress] (called on the main isolate).
  /// Throws on any error raised in the worker.
  static Future<BackgroundIndexResult> run({
    required String sourcePath,
    required String dbPath,
    String? contentHash,
    void Function(int processed, int total)? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();

    await Isolate.spawn(
      _isolateEntry,
      _IndexerArgs(
        sendPort: receivePort.sendPort,
        sourcePath: sourcePath,
        dbPath: dbPath,
        contentHash: contentHash,
      ),
      onError: errorPort.sendPort,
      onExit: receivePort.sendPort,
    );

    final completer = Completer<BackgroundIndexResult>();
    late StreamSubscription<dynamic> sub;
    late StreamSubscription<dynamic> errSub;

    sub = receivePort.listen((message) {
      if (message is _ProgressMessage) {
        onProgress?.call(message.processed, message.total);
      } else if (message is BackgroundIndexResult) {
        completer.complete(message);
        sub.cancel();
        errSub.cancel();
        receivePort.close();
        errorPort.close();
      } else if (message == null) {
        // Isolate exited without sending a result — usually means it threw
        // and we'll see the error via the errorPort.
      }
    });

    errSub = errorPort.listen((dynamic message) {
      if (completer.isCompleted) return;
      // message arrives as [errorString, stackTraceString]
      final list = (message as List?) ?? const [];
      final err = list.isNotEmpty ? list.first.toString() : 'unknown';
      completer.completeError(StateError('Background indexer failed: $err'));
      sub.cancel();
      errSub.cancel();
      receivePort.close();
      errorPort.close();
    });

    return completer.future;
  }
}

class _IndexerArgs {
  const _IndexerArgs({
    required this.sendPort,
    required this.sourcePath,
    required this.dbPath,
    required this.contentHash,
  });
  final SendPort sendPort;
  final String sourcePath;
  final String dbPath;
  final String? contentHash;
}

@immutable
class _ProgressMessage {
  const _ProgressMessage({required this.processed, required this.total});
  final int processed;
  final int total;
}

void _isolateEntry(_IndexerArgs args) {
  final sw = Stopwatch()..start();
  final source = File(args.sourcePath).readAsStringSync();
  final graph = ObjectGraph.parse(source);

  final db = AppDatabase.open(args.dbPath, migrations: cimIndexMigrations);
  try {
    final fileId = Indexer(database: db).indexGraph(
      filePath: args.sourcePath,
      contentHash: args.contentHash,
      graph: graph,
      onProgress: (processed, total) {
        args.sendPort.send(
          _ProgressMessage(processed: processed, total: total),
        );
      },
    );
    sw.stop();
    args.sendPort.send(
      BackgroundIndexResult(
        fileId: fileId,
        elementCount: graph.elementCount,
        totalDuration: sw.elapsed,
      ),
    );
  } finally {
    db.close();
  }
}
