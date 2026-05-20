import 'package:cim_forge/features/schema/class_browser.dart';
import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Metamodel _miniHierarchy() {
  return Metamodel(
    classes: {
      'IdentifiedObject': const CimClass(
        name: 'IdentifiedObject',
        ownAttributes: [
          CimAttribute(
            name: 'name',
            dataType: 'String',
            cardinality: Cardinality.optional,
          ),
        ],
      ),
      'Equipment': const CimClass(
        name: 'Equipment',
        parent: 'IdentifiedObject',
      ),
      'ACLineSegment': const CimClass(
        name: 'ACLineSegment',
        parent: 'Equipment',
        ownAttributes: [
          CimAttribute(
            name: 'r',
            dataType: 'Float',
            cardinality: Cardinality.optional,
          ),
        ],
      ),
    },
  );
}

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('lists classes in hierarchy and prompts for selection', (
    tester,
  ) async {
    final m = _miniHierarchy();
    await _pump(
      tester,
      ClassBrowserPanel(metamodel: m, selected: null, onSelect: (_) {}),
    );

    for (final name in ['IdentifiedObject', 'Equipment', 'ACLineSegment']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(
      find.text('Select a class to see its attributes and associations'),
      findsOneWidget,
    );
  });

  testWidgets('shows inherited attributes for the selected class', (
    tester,
  ) async {
    final m = _miniHierarchy();
    await _pump(
      tester,
      ClassBrowserPanel(
        metamodel: m,
        selected: 'ACLineSegment',
        onSelect: (_) {},
      ),
    );

    // Inherited 'name' from IdentifiedObject.
    expect(find.text('name'), findsOneWidget);
    // Own 'r' on ACLineSegment.
    expect(find.text('r'), findsOneWidget);
    // Inheritance hint includes the chain.
    expect(find.textContaining('Inherits:'), findsOneWidget);
  });

  testWidgets('clicking a class invokes onSelect', (tester) async {
    final m = _miniHierarchy();
    String? picked;
    await _pump(
      tester,
      ClassBrowserPanel(
        metamodel: m,
        selected: null,
        onSelect: (name) => picked = name,
      ),
    );

    await tester.tap(find.text('ACLineSegment'));
    await tester.pump();
    expect(picked, 'ACLineSegment');
  });
}
