import 'dart:async';

typedef SpanSink = void Function(SpanRecord record);

class SpanRecord {
  const SpanRecord({
    required this.name,
    required this.startedAt,
    required this.duration,
    required this.tags,
    required this.error,
  });

  final String name;
  final DateTime startedAt;
  final Duration duration;
  final Map<String, Object?> tags;
  final Object? error;

  @override
  String toString() {
    final tagStr = tags.entries.map((e) => '${e.key}=${e.value}').join(' ');
    final errStr = error != null ? ' error=$error' : '';
    return 'span[$name dur=${duration.inMicroseconds}us $tagStr$errStr]';
  }
}

/// Captures named spans for TR-8 budget tracking and structured logging.
///
/// A single global instance is used by the running app (`Telemetry.instance`);
/// tests instantiate their own to assert recorded spans.
class Telemetry {
  Telemetry({SpanSink? sink}) : _sink = sink ?? _defaultSink;

  static Telemetry instance = Telemetry();

  final SpanSink _sink;
  final List<SpanRecord> _recorded = [];

  List<SpanRecord> get recorded => List.unmodifiable(_recorded);

  void clear() => _recorded.clear();

  /// Runs [body] inside a named span; the elapsed time and any thrown error
  /// are recorded. Tags can be filled while the body runs.
  T span<T>(
    String name,
    T Function(Map<String, Object?> tags) body,
  ) {
    final tags = <String, Object?>{};
    final start = DateTime.now();
    final sw = Stopwatch()..start();
    Object? error;
    try {
      return body(tags);
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      sw.stop();
      _emit(name, start, sw.elapsed, tags, error);
    }
  }

  Future<T> spanAsync<T>(
    String name,
    Future<T> Function(Map<String, Object?> tags) body,
  ) async {
    final tags = <String, Object?>{};
    final start = DateTime.now();
    final sw = Stopwatch()..start();
    Object? error;
    try {
      return await body(tags);
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      sw.stop();
      _emit(name, start, sw.elapsed, tags, error);
    }
  }

  void _emit(
    String name,
    DateTime start,
    Duration duration,
    Map<String, Object?> tags,
    Object? error,
  ) {
    final record = SpanRecord(
      name: name,
      startedAt: start,
      duration: duration,
      tags: Map.unmodifiable(tags),
      error: error,
    );
    _recorded.add(record);
    _sink(record);
  }

  static void _defaultSink(SpanRecord record) {
    // Structured one-liner; downstream observability can replace the sink.
    print(record);
  }
}
