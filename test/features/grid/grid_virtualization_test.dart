import 'package:cim_forge/features/grid/grid_data_source.dart';
import 'package:cim_forge/features/grid/grid_selection.dart';
import 'package:cim_forge/features/grid/grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _viewportWidth = 800;
const double _viewportHeight = 400;

Future<int> _pumpAndCountBuilds(
  WidgetTester tester, {
  required int rowCount,
  int columnCount = 10,
}) async {
  var builds = 0;
  final source = SyntheticGridDataSource(
    rowCount: rowCount,
    columnCount: columnCount,
  );
  addTearDown(source.dispose);
  final selection = GridSelection();
  addTearDown(selection.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _viewportWidth,
            height: _viewportHeight,
            child: CimGridView(
              source: source,
              selection: selection,
              onCellBuild: (_) => builds++,
            ),
          ),
        ),
      ),
    ),
  );
  return builds;
}

void main() {
  group('CimGridView virtualization', () {
    testWidgets('build count does not grow with rowCount (the M1 gate)',
        (tester) async {
      final small = await _pumpAndCountBuilds(tester, rowCount: 100);
      final huge = await _pumpAndCountBuilds(tester, rowCount: 500000);

      // The whole point of virtualization: at 500k rows we must not build
      // anywhere near 500k cells. We allow small variance for cache-extent
      // boundary differences between runs.
      expect(
        huge,
        lessThan(small + 50),
        reason: 'cells built at 500k rows should not exceed 100-row baseline '
            'by more than a tiny margin (small=$small, huge=$huge)',
      );
      expect(
        huge,
        lessThan(2000),
        reason: 'absolute build count must remain bounded by viewport + cache, '
            'not data size (huge=$huge)',
      );
    });

    testWidgets('builds only viewport + cache-extent cells initially',
        (tester) async {
      final builds = await _pumpAndCountBuilds(tester, rowCount: 1000);
      // Viewport is 800x400; header 32 + data 28 → ~14 rows; columns ~120 wide
      // → ~7 cols. With cache extent in both directions we expect on the
      // order of 200-1500 cells.
      expect(builds, greaterThan(50));
      expect(builds, lessThan(2000));
    });
  });

  group('CimGridView rendering', () {
    testWidgets('renders headers and visible cells', (tester) async {
      final source =
          SyntheticGridDataSource(rowCount: 100, columnCount: 5);
      addTearDown(source.dispose);
      final selection = GridSelection();
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: _viewportWidth,
              height: _viewportHeight,
              child: CimGridView(source: source, selection: selection),
            ),
          ),
        ),
      );

      // Header column names appear.
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      // Some data cells from the top-left.
      expect(find.text('R0C0'), findsOneWidget);
      expect(find.text('R0C1'), findsOneWidget);
    });

    testWidgets('selection change repaints (R0C0 stays, focus moves)',
        (tester) async {
      final source =
          SyntheticGridDataSource(rowCount: 100, columnCount: 5);
      addTearDown(source.dispose);
      final selection = GridSelection();
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: _viewportWidth,
              height: _viewportHeight,
              child: CimGridView(source: source, selection: selection),
            ),
          ),
        ),
      );

      selection.moveTo(const CellPosition(2, 1));
      await tester.pump();
      // Just assert no exception and that the cell at the focus is rendered.
      expect(find.text('R2C1'), findsOneWidget);
    });
  });
}
