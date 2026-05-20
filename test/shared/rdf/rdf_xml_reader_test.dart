import 'dart:io';

import 'package:cim_forge/shared/rdf/rdf_xml_reader.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:Equipment.EquipmentContainer rdf:resource="#_sub1"/>
  </cim:ACLineSegment>
</rdf:RDF>
''';

void main() {
  group('readRdfXml', () {
    test('emits start/text/end events with non-null spans', () {
      final events = readRdfXml(_sample).toList();

      for (final e in events) {
        expect(e.span.start, isNonNegative);
        expect(e.span.stop, greaterThan(e.span.start));
      }

      final starts = events.whereType<StartElementEvent>().toList();
      expect(starts.map((e) => e.name), contains('cim:ACLineSegment'));
      expect(starts.map((e) => e.name), contains('cim:IdentifiedObject.name'));
    });

    test('attribute spans point to the actual source literal', () {
      final start = readRdfXml(_sample)
          .whereType<StartElementEvent>()
          .firstWhere((e) => e.name == 'cim:ACLineSegment');

      final idAttr = start.attributes.singleWhere((a) => a.name == 'rdf:ID');
      expect(idAttr.value, '_line1');
      final literal = _sample.substring(idAttr.span.start, idAttr.span.stop);
      expect(literal, 'rdf:ID="_line1"');
    });

    test('self-closing elements report isSelfClosing and no matching end',
        () {
      final events = readRdfXml(_sample).toList();
      final container = events
          .whereType<StartElementEvent>()
          .firstWhere((e) => e.name == 'cim:Equipment.EquipmentContainer');
      expect(container.isSelfClosing, isTrue);

      final ends = events
          .whereType<EndElementEvent>()
          .where((e) => e.name == 'cim:Equipment.EquipmentContainer');
      expect(ends, isEmpty);
    });

    test('byte ranges allow surgical replacement that round-trips', () {
      final lengthText = readRdfXml(_sample)
          .whereType<TextEvent>()
          .firstWhere((e) => e.value.trim() == 'Feeder 12');
      final patched = _sample.replaceRange(
        lengthText.span.start,
        lengthText.span.stop,
        'Renamed Feeder',
      );
      final reparsed = readRdfXml(patched)
          .whereType<TextEvent>()
          .firstWhere((e) => e.value.trim() == 'Renamed Feeder');
      expect(reparsed, isNotNull);
    });
  });

  group('real-world fixtures', () {
    test('ACEP_PSIL fixture parses with every event spanned', () {
      const path = 'test/fixtures/cim/ACEP_PSIL.xml';
      if (!File(path).existsSync()) {
        markTestSkipped('fixture not present: $path');
        return;
      }
      final content = File(path).readAsStringSync();
      final events = readRdfXml(content).toList();
      expect(events, isNotEmpty);
      for (final e in events) {
        expect(e.span.start, isNonNegative);
        expect(e.span.stop, lessThanOrEqualTo(content.length));
        expect(e.span.stop, greaterThan(e.span.start));
      }
    });
  });
}
