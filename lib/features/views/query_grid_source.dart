import 'dart:async';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:meta/meta.dart';

/// Number of rows fetched around any unresolved cell request.
const int _windowSize = 200;

/// Marker returned from `cellAt` while a row's page is still being fetched.
const String _pendingPlaceholder = '…';

/// One resolved grid column — either a direct column from the view definition
/// (base) or a slot/attribute pair from a composite inclusion.
@immutable
sealed class ResolvedColumn {
  const ResolvedColumn({required this.header});
  final String header;
}

class ResolvedBaseColumn extends ResolvedColumn {
  const ResolvedBaseColumn({
    required this.source,
    required this.valueIndex,
    required super.header,
  });

  final ColumnDefinition source;
  final int valueIndex;
}

class ResolvedSlotColumn extends ResolvedColumn {
  const ResolvedSlotColumn({
    required this.inclusionIndex,
    required this.slotIndex,
    required this.attributeIndex,
    required this.attributeName,
    required super.header,
  });

  final int inclusionIndex;
  final int slotIndex;
  final int attributeIndex;
  final String attributeName;
}

/// A [GridDataSource] backed by a [QueryEngine] running against the M3
/// triple-store index. Async row resolution: the grid calls [cellAt]
/// synchronously, and unresolved cells return [_pendingPlaceholder] until
/// the window containing that row has been fetched.
///
/// For composite views (M6) the column list expands every inclusion into
/// `inclusion.maxCount × inclusion.attributes.length` slot columns. Edits
/// route to the base element for base columns and to the child element for
/// slot columns.
class QueryGridSource extends GridDataSource {
  QueryGridSource({
    required this.database,
    required this.engine,
    required ViewDefinition view,
    this.editController,
  }) : _view = view {
    _resolved = _buildResolvedColumns(_view);
    _columns = [
      for (final c in _resolved) GridColumn(header: c.header, width: 140),
    ];
    _rowCount = engine.countMatching(database, _view);
    _ensureWindowFor(0);
    editController?.addListener(_onEditControllerChanged);
  }

  final AppDatabase database;
  final QueryEngine engine;

  /// Optional. When supplied, single-attribute (path-length-1) base columns
  /// and inclusion slot cells are editable via [cellEditor].
  final EditController? editController;

  ViewDefinition _view;
  late List<ResolvedColumn> _resolved;
  late List<GridColumn> _columns;
  late int _rowCount;

  /// Page of fetched rows currently cached. Half-open: `_windowStart` ≤ row
  /// index < `_windowStart + _windowRows.length`.
  int _windowStart = 0;
  List<ViewRow> _windowRows = const [];

  /// True while a page fetch is in flight. We don't run two at once.
  bool _fetching = false;

  /// True after [dispose] — pending fetches short-circuit instead of touching
  /// a closed database.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    editController?.removeListener(_onEditControllerChanged);
    super.dispose();
  }

  void _onEditControllerChanged() {
    // An edit landed on the controller — invalidate the current window so
    // freshly-edited values appear in the grid.
    invalidate();
  }

  @override
  int get rowCount => _rowCount;

  @override
  int get columnCount => _columns.length;

  @override
  GridColumn columnAt(int index) => _columns[index];

  /// True when the row at [row] is currently overflowing
  /// inclusion [inclusionIndex] — FR-2.11. Useful for grid decorations
  /// (e.g. a red marker on the row).
  bool isInclusionOverflowing(int row, int inclusionIndex) {
    if (!_isInWindow(row)) return false;
    final viewRow = _windowRows[row - _windowStart];
    if (inclusionIndex >= viewRow.slots.length) return false;
    return viewRow.slots[inclusionIndex].overflow;
  }

  @override
  String cellAt(int row, int column) {
    if (!_isInWindow(row)) {
      _ensureWindowFor(row);
      return _pendingPlaceholder;
    }
    final viewRow = _windowRows[row - _windowStart];
    final col = _resolved[column];
    return switch (col) {
      ResolvedBaseColumn(:final valueIndex) =>
        viewRow.values[valueIndex] ?? '',
      ResolvedSlotColumn(
        :final inclusionIndex,
        :final slotIndex,
        :final attributeIndex,
      ) =>
        viewRow.slots[inclusionIndex].slots[slotIndex]
                ?.values[attributeIndex] ??
            '',
    };
  }

  /// Returns the element id for the data backing [row], or null if the row
  /// hasn't been fetched yet.
  String? elementIdAt(int row) {
    if (!_isInWindow(row)) return null;
    return _windowRows[row - _windowStart].elementId;
  }

  /// Returns the child element id backing a slot cell, or null if the slot
  /// is empty or the row hasn't been fetched.
  String? childIdAt(int row, int inclusionIndex, int slotIndex) {
    if (!_isInWindow(row)) return null;
    final viewRow = _windowRows[row - _windowStart];
    if (inclusionIndex >= viewRow.slots.length) return null;
    final slot = viewRow.slots[inclusionIndex].slots[slotIndex];
    return slot?.childId;
  }

  @override
  Future<void> Function(String)? cellEditor(int row, int column) {
    final controller = editController;
    if (controller == null) return null;
    if (!_isInWindow(row)) return null;
    final col = _resolved[column];
    return switch (col) {
      ResolvedBaseColumn(:final source) => _baseColumnEditor(
        row: row,
        column: source,
        controller: controller,
      ),
      ResolvedSlotColumn(
        :final inclusionIndex,
        :final slotIndex,
        :final attributeName,
      ) =>
        _slotColumnEditor(
          row: row,
          inclusionIndex: inclusionIndex,
          slotIndex: slotIndex,
          attributeName: attributeName,
          controller: controller,
        ),
    };
  }

  Future<void> Function(String)? _baseColumnEditor({
    required int row,
    required ColumnDefinition column,
    required EditController controller,
  }) {
    if (column.path.length != 1) return null; // joined column reads stay r/o
    final attr = column.path.single;
    final elementId = _windowRows[row - _windowStart].elementId;
    final oldValue =
        controller.currentAttribute(elementId, attr) ?? '';
    return (newValue) async {
      if (newValue == oldValue) return;
      controller.apply(
        SetAttributeValueOp(
          elementId: elementId,
          attributeName: attr,
          newValue: newValue,
          oldValue: oldValue,
        ),
      );
    };
  }

  Future<void> Function(String)? _slotColumnEditor({
    required int row,
    required int inclusionIndex,
    required int slotIndex,
    required String attributeName,
    required EditController controller,
  }) {
    final childId = childIdAt(row, inclusionIndex, slotIndex);
    if (childId == null) {
      // Empty slot — creating-on-edit is a polish item (FR-2.12); for M6 we
      // simply expose no editor.
      return null;
    }
    final oldValue =
        controller.currentAttribute(childId, attributeName) ?? '';
    return (newValue) async {
      if (newValue == oldValue) return;
      controller.apply(
        SetAttributeValueOp(
          elementId: childId,
          attributeName: attributeName,
          newValue: newValue,
          oldValue: oldValue,
        ),
      );
    };
  }

  /// Swap the underlying view (definition changed via CRUD). Refreshes row
  /// count and clears the page cache.
  void setView(ViewDefinition view) {
    _view = view;
    _resolved = _buildResolvedColumns(_view);
    _columns = [
      for (final c in _resolved) GridColumn(header: c.header, width: 140),
    ];
    _rowCount = engine.countMatching(database, _view);
    _windowStart = 0;
    _windowRows = const [];
    notifyListeners();
    _ensureWindowFor(0);
  }

  /// Notifies the grid that the underlying data has changed (e.g. an edit
  /// landed). Refreshes the row count and invalidates the cached window.
  void invalidate() {
    _rowCount = engine.countMatching(database, _view);
    _windowRows = const [];
    notifyListeners();
    _ensureWindowFor(_windowStart);
  }

  bool _isInWindow(int row) =>
      _windowRows.isNotEmpty &&
      row >= _windowStart &&
      row < _windowStart + _windowRows.length;

  void _ensureWindowFor(int row) {
    if (_fetching) return;
    if (_isInWindow(row)) return;
    if (_rowCount == 0) return;
    _fetching = true;
    // Center the page around the requested row (clamped at edges).
    final start = (row - _windowSize ~/ 2).clamp(0, _rowCount);
    unawaited(_fetchWindow(start));
  }

  Future<void> _fetchWindow(int start) async {
    try {
      // Run the query off the current sync stack so the grid frame completes
      // first. Cheap microtask boundary.
      await Future<void>.delayed(Duration.zero);
      if (_disposed) return;
      final rows = engine.execute(
        database,
        _view,
        limit: _windowSize,
        offset: start,
      );
      if (_disposed) return;
      _windowStart = start;
      _windowRows = rows;
      notifyListeners();
    } finally {
      _fetching = false;
    }
  }

  static List<ResolvedColumn> _buildResolvedColumns(ViewDefinition view) {
    final out = <ResolvedColumn>[];
    for (var i = 0; i < view.columns.length; i++) {
      out.add(
        ResolvedBaseColumn(
          source: view.columns[i],
          valueIndex: i,
          header: view.columns[i].displayName(),
        ),
      );
    }
    for (var i = 0; i < view.inclusions.length; i++) {
      final inclusion = view.inclusions[i];
      final label = inclusion.displayLabel();
      for (var slot = 0; slot < inclusion.maxCount; slot++) {
        for (var a = 0; a < inclusion.attributes.length; a++) {
          out.add(
            ResolvedSlotColumn(
              inclusionIndex: i,
              slotIndex: slot,
              attributeIndex: a,
              attributeName: inclusion.attributes[a],
              header: '$label · #${slot + 1} · ${inclusion.attributes[a]}',
            ),
          );
        }
      }
    }
    return out;
  }
}
