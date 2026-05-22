import 'package:cim_forge/features/views/view_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewDefinition JSON', () {
    test('round-trips a minimal definition', () {
      const view = ViewDefinition(
        name: 'Feeders',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['name']),
          ColumnDefinition(path: ['length']),
        ],
      );
      final restored = ViewDefinition.fromJson(view.toJson());
      expect(restored.name, 'Feeders');
      expect(restored.baseClass, 'ACLineSegment');
      expect(restored.columns.length, 2);
      expect(restored.columns.first.path, ['name']);
    });

    test('round-trips joined columns', () {
      const view = ViewDefinition(
        name: 'Feeders+Container',
        baseClass: 'ACLineSegment',
        columns: [
          ColumnDefinition(path: ['EquipmentContainer', 'name']),
        ],
      );
      final restored = ViewDefinition.fromJson(view.toJson());
      expect(restored.columns.single.path, ['EquipmentContainer', 'name']);
      expect(restored.columns.single.displayName(), 'name');
    });

    test('round-trips filters and sort', () {
      const view = ViewDefinition(
        name: 'Sorted',
        baseClass: 'ACLineSegment',
        columns: [ColumnDefinition(path: ['name'])],
        filters: [
          FilterDefinition(
            path: ['name'],
            op: FilterOp.contains,
            value: 'Feeder',
          ),
        ],
        sort: [SortDefinition(path: ['length'], descending: true)],
      );
      final restored = ViewDefinition.fromJson(view.toJson());
      expect(restored.filters.single.op, FilterOp.contains);
      expect(restored.filters.single.value, 'Feeder');
      expect(restored.sort.single.descending, isTrue);
    });

    test('rejects an unknown future formatVersion', () {
      expect(
        () => ViewDefinition.fromJson(const <String, Object?>{
          'formatVersion': 99,
          'name': 'x',
          'baseClass': 'y',
          'columns': <Map<String, Object?>>[],
        }),
        throwsFormatException,
      );
    });

    test('fromJson rejects a column with empty path', () {
      expect(
        () => ColumnDefinition.fromJson(
          const <String, Object?>{'path': <String>[]},
        ),
        throwsFormatException,
      );
    });
  });
}
