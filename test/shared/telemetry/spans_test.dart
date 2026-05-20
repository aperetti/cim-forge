import 'package:cim_forge/shared/telemetry/spans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Telemetry.span', () {
    test('records duration and tags for a sync span', () {
      final records = <SpanRecord>[];
      final t = Telemetry(sink: records.add);

      final result = t.span<int>('compute.thing', (tags) {
        tags['n'] = 42;
        return 7;
      });

      expect(result, 7);
      expect(records, hasLength(1));
      expect(records.single.name, 'compute.thing');
      expect(records.single.tags['n'], 42);
      expect(records.single.error, isNull);
      expect(records.single.duration, greaterThanOrEqualTo(Duration.zero));
    });

    test('records error and rethrows for a failing sync span', () {
      final records = <SpanRecord>[];
      final t = Telemetry(sink: records.add);

      expect(
        () => t.span<int>('boom', (_) => throw StateError('nope')),
        throwsStateError,
      );

      expect(records, hasLength(1));
      expect(records.single.name, 'boom');
      expect(records.single.error, isA<StateError>());
    });

    test('records an async span', () async {
      final records = <SpanRecord>[];
      final t = Telemetry(sink: records.add);

      final result = await t.spanAsync<String>('io.read', (tags) async {
        tags['path'] = '/tmp/x';
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 'ok';
      });

      expect(result, 'ok');
      expect(records.single.name, 'io.read');
      expect(records.single.tags['path'], '/tmp/x');
      expect(
        records.single.duration,
        greaterThanOrEqualTo(const Duration(milliseconds: 5)),
      );
    });

    test('records error and rethrows for a failing async span', () async {
      final records = <SpanRecord>[];
      final t = Telemetry(sink: records.add);

      await expectLater(
        () => t.spanAsync<int>(
          'fail',
          (_) async => throw StateError('async boom'),
        ),
        throwsStateError,
      );

      expect(records.single.error, isA<StateError>());
    });
  });
}
