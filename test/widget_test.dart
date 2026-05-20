import 'package:cim_forge/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell renders the project picker when no project is open',
      (tester) async {
    await tester.pumpWidget(const CimForgeApp());
    await tester.pumpAndSettle();

    expect(find.text('Open a CIM Forge project'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });
}
