import 'dart:io';

import 'package:cim_forge/features/model/object_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObjectGraph.parse on hand-authored sample', () {
    late ObjectGraph g;

    setUpAll(() {
      final src = File('test/fixtures/cim/sample.xml').readAsStringSync();
      g = ObjectGraph.parse(src);
    });

    test('indexes elements by rdf:ID', () {
      expect(g.elementById('_sub1')?.className, 'Substation');
      expect(g.elementById('_line1')?.className, 'ACLineSegment');
      expect(g.elementById('_line2')?.className, 'ACLineSegment');
    });

    test('parses scalar attributes with values', () {
      final line1 = g.elementById('_line1')!;
      expect(line1.attribute('name')?.value, 'Feeder 12');
      expect(line1.attribute('r')?.value, '0.013');
      expect(line1.attribute('Conductor.length')?.value, '1234.5');
    });

    test('parses associations via rdf:resource', () {
      final line1 = g.elementById('_line1')!;
      final assoc = line1.association('EquipmentContainer');
      expect(assoc, isNotNull);
      expect(assoc!.targetId, '_sub1');
    });

    test('every element has non-null spans', () {
      for (final el in g.elements) {
        expect(el.headerSpan.length, greaterThan(0));
        expect(el.idAttributeSpan.length, greaterThan(0));
        for (final a in el.attributes) {
          expect(a.elementSpan.length, greaterThan(0));
          expect(a.textSpan.length, greaterThanOrEqualTo(0));
        }
        for (final a in el.associations) {
          expect(a.elementSpan.length, greaterThan(0));
          expect(a.targetSpan.length, greaterThan(0));
        }
      }
    });

    test('attribute textSpan points at the literal value', () {
      final line1 = g.elementById('_line1')!;
      final rAttr = line1.attribute('r')!;
      final slice = g.source.substring(
        rAttr.textSpan.start,
        rAttr.textSpan.stop,
      );
      expect(slice, '0.013');
    });

    test('association targetSpan points at the rdf:resource literal', () {
      final line1 = g.elementById('_line1')!;
      final assoc = line1.association('EquipmentContainer')!;
      final slice = g.source.substring(
        assoc.targetSpan.start,
        assoc.targetSpan.stop,
      );
      expect(slice, 'rdf:resource="#_sub1"');
    });

    test('id-attribute span points at the rdf:ID literal', () {
      final line1 = g.elementById('_line1')!;
      final slice = g.source.substring(
        line1.idAttributeSpan.start,
        line1.idAttributeSpan.stop,
      );
      expect(slice, 'rdf:ID="_line1"');
    });
  });

  group('ObjectGraph.parse on real-world fixture', () {
    test('ACEP_PSIL parses with every property spanned', () {
      const path = 'test/fixtures/cim/ACEP_PSIL.xml';
      if (!File(path).existsSync()) {
        markTestSkipped('fixture not present: $path');
        return;
      }
      final src = File(path).readAsStringSync();
      final g = ObjectGraph.parse(src);
      expect(g.elementCount, greaterThan(10));
      for (final el in g.elements) {
        expect(el.id, isNotEmpty);
        for (final a in el.attributes) {
          expect(a.textSpan.start, greaterThanOrEqualTo(el.headerSpan.start));
          expect(a.textSpan.stop, lessThanOrEqualTo(src.length));
        }
      }
    });
  });
}
