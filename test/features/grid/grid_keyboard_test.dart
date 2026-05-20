import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:cim_forge/features/grid/grid_selection.dart';
import 'package:cim_forge/features/grid/grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({GridDataSource source, GridSelection selection})> _pumpGrid(
  WidgetTester tester, {
  int rowCount = 50,
  int columnCount = 8,
  CellPosition initialFocus = const CellPosition(0, 0),
}) async {
  final source = SyntheticGridDataSource(
    rowCount: rowCount,
    columnCount: columnCount,
  );
  addTearDown(source.dispose);
  final selection = GridSelection(initialFocus: initialFocus);
  addTearDown(selection.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: CimGridView(source: source, selection: selection),
        ),
      ),
    ),
  );
  // Settle focus.
  await tester.pump();
  return (source: source, selection: selection);
}

void main() {
  group('CimGridView keyboard navigation', () {
    testWidgets('arrow keys move focus and collapse selection',
        (tester) async {
      final h = await _pumpGrid(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(h.selection.focus, const CellPosition(1, 1));
      expect(h.selection.range.cellCount, 1);
    });

    testWidgets('arrow keys clamp at the edges', (tester) async {
      final h = await _pumpGrid(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // already at 0,0
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(h.selection.focus, const CellPosition(0, 0));
    });

    testWidgets('shift+arrow extends selection while keeping anchor',
        (tester) async {
      final h = await _pumpGrid(
        tester,
        initialFocus: const CellPosition(2, 2),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(h.selection.anchor, const CellPosition(2, 2));
      expect(h.selection.focus, const CellPosition(3, 3));
      expect(h.selection.range.cellCount, 4);
    });

    testWidgets('pageDown moves focus by the page step', (tester) async {
      final h = await _pumpGrid(tester, rowCount: 100);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(h.selection.focus.row, 10);
    });

    testWidgets('ctrl+home jumps to (0, 0)', (tester) async {
      final h = await _pumpGrid(
        tester,
        initialFocus: const CellPosition(5, 4),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(h.selection.focus, const CellPosition(0, 0));
    });

    testWidgets('ctrl+end jumps to bottom-right', (tester) async {
      final h = await _pumpGrid(
        tester,
        rowCount: 20,
        columnCount: 6,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(h.selection.focus, const CellPosition(19, 5));
    });

    testWidgets('ctrl+c writes the selection TSV to the clipboard',
        (tester) async {
      // Capture clipboard writes via a mock platform-channel handler.
      String? capturedText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<Object?, Object?>;
                capturedText = args['text'] as String?;
              }
              return null;
            });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final h = await _pumpGrid(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(h.selection.range.cellCount, 4);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(capturedText, 'R0C0\tR0C1\nR1C0\tR1C1');
    });
  });
}
