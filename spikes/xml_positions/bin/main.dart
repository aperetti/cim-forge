// Spike TR-9.1 — XML source-position fidelity.
//
// Question: does the `xml` package expose char offsets for ELEMENTS and,
// crucially, for individual ATTRIBUTES — enough to anchor surgical patches?
//
// We test the event API (parseEvents), since the DOM API (XmlDocument.parse)
// is known not to carry source positions.

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const sample = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <!-- a comment that surgical patching must preserve -->
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:ACLineSegment.r>0.013</cim:ACLineSegment.r>
    <cim:Conductor.length>1234.5</cim:Conductor.length>
    <cim:Equipment.EquipmentContainer rdf:resource="#_substationA"/>
  </cim:ACLineSegment>
</rdf:RDF>
''';

void main() {
  print('=== xml package: event-level source positions ===\n');

  final events = parseEvents(sample, withLocation: true);

  var elementOffsetsPresent = false;
  var attributeOffsetsPresent = false;
  var textOffsetsPresent = false;

  for (final event in events) {
    final start = event.start;
    final stop = event.stop;

    if (event is XmlStartElementEvent) {
      if (start != null && stop != null) elementOffsetsPresent = true;
      print('START <${event.name}>  start=$start stop=$stop');
      for (final attr in event.attributes) {
        // XmlEventAttribute carries NO offsets — only name/value/type.
        print('   @${attr.name}="${attr.value}"  (no offset on attribute)');
      }
      // But we CAN locate an attribute by rescanning the element's own span.
      if (start != null && stop != null && event.attributes.isNotEmpty) {
        final span = sample.substring(start, stop);
        for (final attr in event.attributes) {
          final needle = '${attr.name}="${attr.value}"';
          final idxInSpan = span.indexOf(needle);
          if (idxInSpan >= 0) {
            attributeOffsetsPresent = true;
            final absStart = start + idxInSpan;
            print('     -> @${attr.name} locatable at abs[$absStart:'
                '${absStart + needle.length}] via span rescan');
          }
        }
      }
    } else if (event is XmlTextEvent) {
      final t = event.value.trim();
      if (t.isNotEmpty) {
        if (start != null && stop != null) textOffsetsPresent = true;
        print('TEXT "$t"  start=$start stop=$stop');
      }
    } else if (event is XmlEndElementEvent) {
      print('END   </${event.name}>  start=$start stop=$stop');
    }
  }

  print('\n=== Verdict ===');
  print('element offsets present:   $elementOffsetsPresent');
  print('attribute offsets present: $attributeOffsetsPresent');
  print('text offsets present:      $textOffsetsPresent');

  // Prove we can actually slice the source by offset and patch a value.
  print('\n=== Surgical slice test ===');
  for (final event in parseEvents(sample, withLocation: true)) {
    if (event is XmlTextEvent && event.value.trim() == '1234.5') {
      final s = event.start!, e = event.stop!;
      final patched = sample.replaceRange(s, e, '9999.9');
      final reparsed = XmlDocument.parse(patched);
      final len = reparsed
          .findAllElements('cim:Conductor.length')
          .single
          .innerText;
      print('sliced source[$s:$e] = "${sample.substring(s, e)}"');
      print('patched length value -> "$len"');
      print(len == '9999.9'
          ? 'PASS: offset-anchored patch round-trips'
          : 'FAIL: patch did not round-trip');
    }
  }
}
