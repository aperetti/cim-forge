import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:flutter/foundation.dart';

/// Inclusive 2D cell range — [anchor] is where selection started, [focus] is
/// the active end. Range covers all cells in the rectangle from anchor to
/// focus inclusive, in either direction.
@immutable
class CellRange {
  const CellRange({required this.anchor, required this.focus});

  const CellRange.single(CellPosition position)
    : anchor = position,
      focus = position;

  final CellPosition anchor;
  final CellPosition focus;

  int get topRow => anchor.row < focus.row ? anchor.row : focus.row;
  int get bottomRow => anchor.row > focus.row ? anchor.row : focus.row;
  int get leftColumn =>
      anchor.column < focus.column ? anchor.column : focus.column;
  int get rightColumn =>
      anchor.column > focus.column ? anchor.column : focus.column;

  int get rowCount => bottomRow - topRow + 1;
  int get columnCount => rightColumn - leftColumn + 1;
  int get cellCount => rowCount * columnCount;

  bool contains(CellPosition position) =>
      position.row >= topRow &&
      position.row <= bottomRow &&
      position.column >= leftColumn &&
      position.column <= rightColumn;

  @override
  bool operator ==(Object other) =>
      other is CellRange && other.anchor == anchor && other.focus == focus;

  @override
  int get hashCode => Object.hash(anchor, focus);

  @override
  String toString() =>
      'CellRange(anchor=$anchor, focus=$focus, '
      'rows=$rowCount, cols=$columnCount)';
}

/// Mutable selection state — exposes a single [range] (anchor + focus). The
/// focus is the "active cell" that receives keyboard input and rendering
/// emphasis; the anchor is the opposite corner of any extended selection.
class GridSelection extends ChangeNotifier {
  GridSelection({CellPosition initialFocus = const CellPosition(0, 0)})
    : _range = CellRange.single(initialFocus);

  CellRange _range;
  CellRange get range => _range;
  CellPosition get focus => _range.focus;
  CellPosition get anchor => _range.anchor;

  /// Replace the selection with a single cell at [position]. Collapses any
  /// extended selection.
  void moveTo(CellPosition position) {
    if (_range.anchor == position && _range.focus == position) return;
    _range = CellRange.single(position);
    notifyListeners();
  }

  /// Move focus by [rowDelta]/[columnDelta], clamping to [0, rowCount) and
  /// [0, columnCount), and collapse the selection.
  void moveBy({
    required int rowDelta,
    required int columnDelta,
    required int rowCount,
    required int columnCount,
  }) {
    final next = _clamp(
      CellPosition(focus.row + rowDelta, focus.column + columnDelta),
      rowCount,
      columnCount,
    );
    moveTo(next);
  }

  /// Extend the selection by moving the focus while keeping the anchor.
  void extendBy({
    required int rowDelta,
    required int columnDelta,
    required int rowCount,
    required int columnCount,
  }) {
    final next = _clamp(
      CellPosition(focus.row + rowDelta, focus.column + columnDelta),
      rowCount,
      columnCount,
    );
    if (next == focus) return;
    _range = CellRange(anchor: anchor, focus: next);
    notifyListeners();
  }

  /// Extend the selection to [position] (keeps the existing anchor).
  void extendTo(CellPosition position) {
    if (position == focus) return;
    _range = CellRange(anchor: anchor, focus: position);
    notifyListeners();
  }

  CellPosition _clamp(CellPosition p, int rowCount, int columnCount) =>
      CellPosition(
        p.row.clamp(0, rowCount - 1),
        p.column.clamp(0, columnCount - 1),
      );
}

/// Serializes [range] from [source] as tab-separated rows, newline-separated.
/// Matches Excel/Sheets clipboard format.
String selectionAsTsv(CellRange range, GridDataSource source) {
  final buf = StringBuffer();
  for (var r = range.topRow; r <= range.bottomRow; r++) {
    for (var c = range.leftColumn; c <= range.rightColumn; c++) {
      if (c > range.leftColumn) buf.write('\t');
      buf.write(source.cellAt(r, c));
    }
    if (r < range.bottomRow) buf.write('\n');
  }
  return buf.toString();
}
