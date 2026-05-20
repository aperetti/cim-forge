import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:cim_forge/features/grid/grid_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

const double _headerRowHeight = 32;
const double _dataRowHeight = 28;
const double _resizeHandleWidth = 8;
const double _minColumnWidth = 40;
const int _pageStep = 10;

/// Stable Key for the resize handle of [columnIndex]. Public so tests can
/// target the handle without scraping internal layout.
Key cimGridResizeHandleKey(int columnIndex) =>
    ValueKey<String>('cim-grid-resize-handle-$columnIndex');

/// A virtualized, read-only spreadsheet-like grid backed by a [GridDataSource]
/// and a [GridSelection]. Only cells in the viewport (plus cache margin) are
/// built — the build count must not grow with [GridDataSource.rowCount].
class CimGridView extends StatefulWidget {
  const CimGridView({
    required this.source,
    required this.selection,
    this.onCellBuild,
    super.key,
  });

  final GridDataSource source;
  final GridSelection selection;

  /// Test hook — invoked once per cell build with the cell's vicinity. The
  /// virtualization gate uses this to assert build count is bounded by the
  /// viewport.
  final ValueChanged<TableVicinity>? onCellBuild;

  @override
  State<CimGridView> createState() => _CimGridViewState();
}

class _CimGridViewState extends State<CimGridView> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'CimGridView');
  final FocusNode _editorFocus = FocusNode(debugLabel: 'CimGridView.editor');
  final TextEditingController _editorController = TextEditingController();

  /// When non-null, the cell at this position is currently in edit mode.
  CellPosition? _editingPosition;

  /// Error from the most recent edit attempt — surfaced as a transient bar.
  String? _editError;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onChange);
    widget.selection.addListener(_onChange);
  }

  @override
  void didUpdateWidget(CimGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_onChange);
      widget.source.addListener(_onChange);
    }
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onChange);
      widget.selection.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _editorFocus.dispose();
    _editorController.dispose();
    widget.source.removeListener(_onChange);
    widget.selection.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_editingPosition != null) return KeyEventResult.ignored;
    final source = widget.source;
    final selection = widget.selection;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    if (event.logicalKey == LogicalKeyboardKey.f2 ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_tryStartEdit(selection.focus)) {
        return KeyEventResult.handled;
      }
    }

    int? rowDelta;
    int? columnDelta;
    final logical = event.logicalKey;

    if (logical == LogicalKeyboardKey.arrowDown) {
      rowDelta = 1;
      columnDelta = 0;
    } else if (logical == LogicalKeyboardKey.arrowUp) {
      rowDelta = -1;
      columnDelta = 0;
    } else if (logical == LogicalKeyboardKey.arrowRight) {
      rowDelta = 0;
      columnDelta = 1;
    } else if (logical == LogicalKeyboardKey.arrowLeft) {
      rowDelta = 0;
      columnDelta = -1;
    } else if (logical == LogicalKeyboardKey.pageDown) {
      rowDelta = _pageStep;
      columnDelta = 0;
    } else if (logical == LogicalKeyboardKey.pageUp) {
      rowDelta = -_pageStep;
      columnDelta = 0;
    } else if (logical == LogicalKeyboardKey.home) {
      _jump(toRow: ctrl ? 0 : selection.focus.row, toColumn: 0, extend: shift);
      return KeyEventResult.handled;
    } else if (logical == LogicalKeyboardKey.end) {
      _jump(
        toRow: ctrl ? source.rowCount - 1 : selection.focus.row,
        toColumn: source.columnCount - 1,
        extend: shift,
      );
      return KeyEventResult.handled;
    } else if (ctrl && logical == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }

    if (rowDelta == null || columnDelta == null) return KeyEventResult.ignored;

    final move = shift ? selection.extendBy : selection.moveBy;
    move(
      rowDelta: rowDelta,
      columnDelta: columnDelta,
      rowCount: source.rowCount,
      columnCount: source.columnCount,
    );
    return KeyEventResult.handled;
  }

  void _jump({
    required int toRow,
    required int toColumn,
    required bool extend,
  }) {
    final target = CellPosition(toRow, toColumn);
    if (extend) {
      widget.selection.extendTo(target);
    } else {
      widget.selection.moveTo(target);
    }
  }

  Future<void> _copySelection() async {
    final tsv = selectionAsTsv(widget.selection.range, widget.source);
    await Clipboard.setData(ClipboardData(text: tsv));
  }

  bool _tryStartEdit(CellPosition position) {
    final editor = widget.source.cellEditor(position.row, position.column);
    if (editor == null) return false;
    _editorController.text =
        widget.source.cellAt(position.row, position.column);
    setState(() {
      _editingPosition = position;
      _editError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocus.requestFocus();
      _editorController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editorController.text.length,
      );
    });
    return true;
  }

  Future<void> _commitEdit() async {
    final pos = _editingPosition;
    if (pos == null) return;
    final editor = widget.source.cellEditor(pos.row, pos.column);
    if (editor == null) {
      setState(() => _editingPosition = null);
      return;
    }
    final value = _editorController.text;
    try {
      await editor(value);
      setState(() {
        _editingPosition = null;
        _editError = null;
      });
      _focusNode.requestFocus();
    } on Object catch (e) {
      setState(() => _editError = e.toString());
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingPosition = null;
      _editError = null;
    });
    _focusNode.requestFocus();
  }

  void _resizeColumn(int index, double delta) {
    final source = widget.source;
    if (source is! SyntheticGridDataSource) return;
    final current = source.columnAt(index).width;
    final next = (current + delta).clamp(_minColumnWidth, double.infinity);
    if (next == current) return;
    source.resizeColumn(index, next);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final selection = widget.selection;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        if (_editError != null)
          Container(
            width: double.infinity,
            color: scheme.errorContainer,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: Text(
              _editError!,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        Expanded(
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _focusNode.requestFocus,
              child: _buildTable(source, selection, scheme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(
    GridDataSource source,
    GridSelection selection,
    ColorScheme scheme,
  ) {
    return TableView.builder(
      pinnedRowCount: 1,
      columnCount: source.columnCount,
      rowCount: source.rowCount + 1, // +1 for the header row
      columnBuilder: (index) => TableSpan(
        extent: FixedTableSpanExtent(source.columnAt(index).width),
        foregroundDecoration: TableSpanDecoration(
          border: TableSpanBorder(
            trailing: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      rowBuilder: (index) => TableSpan(
        extent: FixedTableSpanExtent(
          index == 0 ? _headerRowHeight : _dataRowHeight,
        ),
        foregroundDecoration: TableSpanDecoration(
          border: TableSpanBorder(
            trailing: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        backgroundDecoration: index == 0
            ? TableSpanDecoration(color: scheme.surfaceContainerHighest)
            : null,
      ),
      cellBuilder: (context, vicinity) {
        widget.onCellBuild?.call(vicinity);
        if (vicinity.row == 0) {
          return TableViewCell(
            child: _HeaderCell(
              columnIndex: vicinity.column,
              text: source.columnAt(vicinity.column).header,
              onResizeDelta: (delta) => _resizeColumn(vicinity.column, delta),
            ),
          );
        }
        final dataRow = vicinity.row - 1;
        final position = CellPosition(dataRow, vicinity.column);
        final inSelection = selection.range.contains(position);
        final isFocus = selection.focus == position;
        final isEditing = _editingPosition == position;
        return TableViewCell(
          child: isEditing
              ? _EditCell(
                  controller: _editorController,
                  focusNode: _editorFocus,
                  onSubmit: _commitEdit,
                  onCancel: _cancelEdit,
                )
              : _DataCell(
                  text: source.cellAt(dataRow, vicinity.column),
                  selected: inSelection,
                  focused: isFocus,
                ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.columnIndex,
    required this.text,
    required this.onResizeDelta,
  });

  final int columnIndex;
  final String text;
  final ValueChanged<double> onResizeDelta;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _resizeHandleWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: cimGridResizeHandleKey(columnIndex),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  onResizeDelta(details.delta.dx),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditCell extends StatelessWidget {
  const _EditCell({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _CancelEditIntent(),
      },
      child: Actions(
        actions: {
          _CancelEditIntent: CallbackAction<_CancelEditIntent>(
            onInvoke: (_) {
              onCancel();
              return null;
            },
          ),
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _CancelEditIntent extends Intent {
  const _CancelEditIntent();
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    required this.text,
    required this.selected,
    required this.focused,
  });

  final String text;
  final bool selected;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : null;
    final border = focused
        ? Border.all(color: scheme.primary, width: 1.5)
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(color: background, border: border),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
