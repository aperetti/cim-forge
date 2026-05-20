import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:cim_forge/features/grid/grid_selection.dart';
import 'package:cim_forge/features/grid/grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging a column header edge resizes the column', (
    tester,
  ) async {
    final source = SyntheticGridDataSource(rowCount: 5, columnCount: 4);
    addTearDown(source.dispose);
    final selection = GridSelection();
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: CimGridView(source: source, selection: selection),
          ),
        ),
      ),
    );

    final initialWidth = source.columnAt(0).width;
    // Drag well past touch slop (~18 px). Exact post-slop delta is brittle
    // across Flutter versions; assert direction + magnitude bounds instead.
    await tester.drag(
      find.byKey(cimGridResizeHandleKey(0)),
      const Offset(100, 0),
    );
    await tester.pump();

    final newWidth = source.columnAt(0).width;
    expect(newWidth, greaterThan(initialWidth + 50));
    expect(newWidth, lessThanOrEqualTo(initialWidth + 100));
  });

  testWidgets('column width is clamped to the minimum on large negative drag',
      (tester) async {
    final source = SyntheticGridDataSource(rowCount: 5, columnCount: 4);
    addTearDown(source.dispose);
    final selection = GridSelection();
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 200,
            child: CimGridView(source: source, selection: selection),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(cimGridResizeHandleKey(0)),
      const Offset(-500, 0),
    );
    await tester.pump();

    expect(source.columnAt(0).width, greaterThanOrEqualTo(40));
  });
}
