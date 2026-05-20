import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:cim_forge/features/grid/grid_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CellRange', () {
    test('single-cell range has 1x1 dimensions', () {
      const range = CellRange.single(CellPosition(2, 3));
      expect(range.topRow, 2);
      expect(range.bottomRow, 2);
      expect(range.leftColumn, 3);
      expect(range.rightColumn, 3);
      expect(range.cellCount, 1);
    });

    test('normalizes anchor/focus order in either direction', () {
      const r1 = CellRange(
        anchor: CellPosition(5, 5),
        focus: CellPosition(2, 2),
      );
      expect(r1.topRow, 2);
      expect(r1.bottomRow, 5);
      expect(r1.leftColumn, 2);
      expect(r1.rightColumn, 5);
      expect(r1.rowCount, 4);
      expect(r1.columnCount, 4);
      expect(r1.cellCount, 16);
    });

    test('contains reports cells inside the rectangle', () {
      const r = CellRange(
        anchor: CellPosition(1, 1),
        focus: CellPosition(3, 3),
      );
      expect(r.contains(const CellPosition(2, 2)), isTrue);
      expect(r.contains(const CellPosition(1, 1)), isTrue);
      expect(r.contains(const CellPosition(3, 3)), isTrue);
      expect(r.contains(const CellPosition(0, 2)), isFalse);
      expect(r.contains(const CellPosition(4, 4)), isFalse);
    });
  });

  group('GridSelection', () {
    test('starts at the initial focus as a single cell', () {
      final sel = GridSelection(initialFocus: const CellPosition(2, 3));
      expect(sel.focus, const CellPosition(2, 3));
      expect(sel.range.cellCount, 1);
    });

    test('moveTo collapses to a single cell and notifies', () {
      final sel = GridSelection();
      var notified = 0;
      sel
        ..addListener(() => notified++)
        ..moveTo(const CellPosition(4, 5));
      expect(sel.focus, const CellPosition(4, 5));
      expect(sel.range.cellCount, 1);
      expect(notified, 1);

      // No-op move does not notify.
      sel.moveTo(const CellPosition(4, 5));
      expect(notified, 1);
    });

    test('moveBy clamps and collapses', () {
      final sel = GridSelection()
        ..moveBy(rowDelta: -5, columnDelta: -5, rowCount: 10, columnCount: 10);
      expect(sel.focus, const CellPosition(0, 0));

      sel.moveBy(rowDelta: 100, columnDelta: 3, rowCount: 10, columnCount: 10);
      expect(sel.focus, const CellPosition(9, 3));
      expect(sel.range.cellCount, 1);
    });

    test('extendBy holds anchor and extends focus', () {
      final sel = GridSelection(initialFocus: const CellPosition(2, 2))
        ..extendBy(rowDelta: 2, columnDelta: 1, rowCount: 10, columnCount: 10);
      expect(sel.anchor, const CellPosition(2, 2));
      expect(sel.focus, const CellPosition(4, 3));
      expect(sel.range.cellCount, 6);
    });

    test('extendTo holds anchor and moves focus to position', () {
      final sel = GridSelection(initialFocus: const CellPosition(1, 1))
        ..extendTo(const CellPosition(3, 4));
      expect(sel.anchor, const CellPosition(1, 1));
      expect(sel.focus, const CellPosition(3, 4));
      expect(sel.range.rowCount, 3);
      expect(sel.range.columnCount, 4);
    });

    test('moveTo after extend collapses', () {
      final sel = GridSelection(initialFocus: const CellPosition(1, 1))
        ..extendTo(const CellPosition(3, 3))
        ..moveTo(const CellPosition(5, 5));
      expect(sel.anchor, const CellPosition(5, 5));
      expect(sel.focus, const CellPosition(5, 5));
      expect(sel.range.cellCount, 1);
    });
  });

  group('selectionAsTsv', () {
    test('serializes a 2x3 range tab/newline-delimited', () {
      final source = SyntheticGridDataSource(rowCount: 10, columnCount: 10);
      const range = CellRange(
        anchor: CellPosition(0, 0),
        focus: CellPosition(1, 2),
      );
      expect(
        selectionAsTsv(range, source),
        'R0C0\tR0C1\tR0C2\nR1C0\tR1C1\tR1C2',
      );
    });

    test('single-cell range has no separators', () {
      final source = SyntheticGridDataSource(rowCount: 5, columnCount: 5);
      const range = CellRange.single(CellPosition(2, 3));
      expect(selectionAsTsv(range, source), 'R2C3');
    });
  });
}
