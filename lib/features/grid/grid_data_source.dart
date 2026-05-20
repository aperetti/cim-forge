import 'package:flutter/foundation.dart';

@immutable
class CellPosition {
  const CellPosition(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellPosition && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'CellPosition(r=$row, c=$column)';
}

@immutable
class GridColumn {
  const GridColumn({required this.header, required this.width});

  final String header;
  final double width;

  GridColumn copyWith({String? header, double? width}) =>
      GridColumn(header: header ?? this.header, width: width ?? this.width);
}

/// Random-access, observable source of grid cells.
///
/// The widget reads cells synchronously during build/paint. When the
/// underlying data changes (e.g. a query result streams in, an edit lands),
/// implementations call [notifyListeners] so the grid repaints. Cells that
/// are not yet resolved
/// may return a placeholder string (or empty) without throwing — async
/// resolution will be added in M3 alongside the SQLite-backed source.
abstract class GridDataSource extends ChangeNotifier {
  int get rowCount;
  int get columnCount;

  GridColumn columnAt(int index);
  String cellAt(int row, int column);

  /// Returns a function the grid can call to commit a new string value into
  /// the cell at [row]/[column], or null if that cell is read-only. The
  /// function may throw to signal a validation failure; the caller is
  /// expected to surface the error to the user.
  Future<void> Function(String)? cellEditor(int row, int column) => null;
}

/// A synthetic source for tests and the M1 perf demo. Generates cell values
/// deterministically from `(row, column)` so we can exercise the widget at
/// arbitrary scale without holding millions of strings in memory.
class SyntheticGridDataSource extends GridDataSource {
  SyntheticGridDataSource({
    required this.rowCount,
    required int columnCount,
    double columnWidth = 120,
  }) : _columns = List.generate(
         columnCount,
         (i) => GridColumn(header: _defaultHeader(i), width: columnWidth),
       );

  @override
  final int rowCount;

  final List<GridColumn> _columns;

  @override
  int get columnCount => _columns.length;

  @override
  GridColumn columnAt(int index) => _columns[index];

  @override
  String cellAt(int row, int column) {
    _assertInRange(row, column);
    return 'R${row}C$column';
  }

  /// Updates the width of [columnIndex]. Notifies listeners.
  void resizeColumn(int columnIndex, double width) {
    _columns[columnIndex] = _columns[columnIndex].copyWith(width: width);
    notifyListeners();
  }

  void _assertInRange(int row, int column) {
    if (row < 0 || row >= rowCount) {
      throw RangeError.range(row, 0, rowCount - 1, 'row');
    }
    if (column < 0 || column >= columnCount) {
      throw RangeError.range(column, 0, columnCount - 1, 'column');
    }
  }

  static String _defaultHeader(int index) {
    // A, B, ..., Z, AA, AB, ... — Excel-style column names.
    var n = index;
    final buf = StringBuffer();
    do {
      buf.write(String.fromCharCode(65 + n % 26));
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return buf.toString().split('').reversed.join();
  }
}
