import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyntheticGridDataSource', () {
    test('cells are generated deterministically from (row, col)', () {
      final source = SyntheticGridDataSource(rowCount: 10, columnCount: 5);
      expect(source.cellAt(0, 0), 'R0C0');
      expect(source.cellAt(3, 4), 'R3C4');
      expect(source.cellAt(9, 0), 'R9C0');
    });

    test('rejects out-of-range rows and columns', () {
      final source = SyntheticGridDataSource(rowCount: 3, columnCount: 3);
      expect(() => source.cellAt(-1, 0), throwsRangeError);
      expect(() => source.cellAt(3, 0), throwsRangeError);
      expect(() => source.cellAt(0, -1), throwsRangeError);
      expect(() => source.cellAt(0, 3), throwsRangeError);
    });

    test('default headers follow Excel-style sequence', () {
      final source = SyntheticGridDataSource(rowCount: 1, columnCount: 30);
      expect(source.columnAt(0).header, 'A');
      expect(source.columnAt(25).header, 'Z');
      expect(source.columnAt(26).header, 'AA');
      expect(source.columnAt(27).header, 'AB');
    });

    test('resizeColumn updates width and notifies listeners', () {
      var notifications = 0;
      final source = SyntheticGridDataSource(rowCount: 2, columnCount: 3)
        ..addListener(() => notifications++)
        ..resizeColumn(1, 240);
      expect(source.columnAt(1).width, 240);
      expect(notifications, 1);
    });

    test('scales to large row counts without allocation', () {
      final source = SyntheticGridDataSource(rowCount: 500000, columnCount: 50);
      expect(source.rowCount, 500000);
      expect(source.cellAt(499999, 49), 'R499999C49');
    });
  });

  group('CellPosition', () {
    test('equality and hashCode', () {
      expect(const CellPosition(1, 2), const CellPosition(1, 2));
      expect(const CellPosition(1, 2).hashCode,
          const CellPosition(1, 2).hashCode);
      expect(const CellPosition(1, 2) == const CellPosition(2, 1), isFalse);
    });
  });
}
