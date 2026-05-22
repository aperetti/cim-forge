import 'dart:io';

import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/xml_patch/canonical_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips a hand-authored sample to a graph-equivalent state', () {
    final source =
        File('test/fixtures/cim/sample.xml').readAsStringSync();
    final original = ObjectGraph.parse(source);
    final canonical = const CanonicalSerializer().serialize(original);
    final reparsed = ObjectGraph.parse(canonical);

    expect(reparsed.elementCount, original.elementCount);
    for (final el in original.elements) {
      final back = reparsed.elementById(el.id);
      expect(back, isNotNull,
          reason: '${el.id} disappeared after canonicalize');
      expect(back!.className, el.className);
      for (final attr in el.attributes) {
        expect(
          back.attribute(attr.shortName)?.value,
          attr.value,
          reason: '${el.id}.${attr.shortName}',
        );
      }
      for (final assoc in el.associations) {
        expect(
          back.association(assoc.shortName)?.targetId,
          assoc.targetId,
          reason: '${el.id}.${assoc.shortName}',
        );
      }
    }
  });

  test('round-trips the real-world ACEP_PSIL fixture', () {
    const path = 'test/fixtures/cim/ACEP_PSIL.xml';
    if (!File(path).existsSync()) {
      markTestSkipped('fixture not present: $path');
      return;
    }
    final source = File(path).readAsStringSync();
    final original = ObjectGraph.parse(source);
    final canonical = const CanonicalSerializer().serialize(original);
    final reparsed = ObjectGraph.parse(canonical);

    expect(reparsed.elementCount, original.elementCount);
    for (final el in original.elements.take(20)) {
      final back = reparsed.elementById(el.id)!;
      expect(back.className, el.className);
      for (final attr in el.attributes) {
        expect(back.attribute(attr.shortName)?.value, attr.value);
      }
    }
  });

  test('sorts elements by id alphabetically in the output', () {
    final source =
        File('test/fixtures/cim/sample_composite.xml').readAsStringSync();
    final canonical =
        const CanonicalSerializer().serialize(ObjectGraph.parse(source));
    // Slot order in output should be _lineA, _lineB, _lineC, _lineD, _sub1.
    final lineAIdx = canonical.indexOf('rdf:ID="_lineA"');
    final lineDIdx = canonical.indexOf('rdf:ID="_lineD"');
    final subIdx = canonical.indexOf('rdf:ID="_sub1"');
    expect(lineAIdx, lessThan(lineDIdx));
    expect(lineDIdx, lessThan(subIdx));
  });

  test('correctly escapes XML special characters in attribute text', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:Substation rdf:ID="_sub1">
    <cim:IdentifiedObject.name>A &amp; B &lt;c&gt;</cim:IdentifiedObject.name>
  </cim:Substation>
</rdf:RDF>
''';
    final graph = ObjectGraph.parse(xml);
    final canonical = const CanonicalSerializer().serialize(graph);
    expect(canonical, contains('A &amp; B &lt;c&gt;'));
    final reparsed = ObjectGraph.parse(canonical);
    expect(
      reparsed.elementById('_sub1')?.attribute('name')?.value,
      'A & B <c>',
    );
  });
}
