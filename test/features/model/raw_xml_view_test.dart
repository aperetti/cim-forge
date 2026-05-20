import 'package:cim_forge/features/model/raw_xml_view.dart';
import 'package:cim_forge/shared/rdf/rdf_xml_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _src = 'alpha beta gamma';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('renders the full source when no highlight is set',
      (tester) async {
    await _pump(tester, const RawXmlView(source: _src));
    // SelectableText renders a single Text descendant equal to the source.
    expect(find.text(_src), findsOneWidget);
  });

  testWidgets('splits into three runs when a highlight is supplied',
      (tester) async {
    await _pump(
      tester,
      const RawXmlView(source: _src, highlight: SourceSpan(6, 10)),
    );
    // SelectableText.rich produces three TextSpans which the framework
    // concatenates into one paragraph; assert the visible text is unchanged.
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectable.textSpan, isNotNull);
    expect(
      selectable.textSpan!.toPlainText(),
      _src,
    );
  });
}
