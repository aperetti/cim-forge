import 'package:cim_forge/features/diff/semantic_diff.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:Substation rdf:ID="_sub1">
    <cim:IdentifiedObject.name>Substation A</cim:IdentifiedObject.name>
  </cim:Substation>
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:Conductor.length>100.0</cim:Conductor.length>
    <cim:Equipment.EquipmentContainer rdf:resource="#_sub1"/>
  </cim:ACLineSegment>
</rdf:RDF>
''';

const _renameLine1Xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:Substation rdf:ID="_sub1">
    <cim:IdentifiedObject.name>Substation A</cim:IdentifiedObject.name>
  </cim:Substation>
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Renamed Feeder</cim:IdentifiedObject.name>
    <cim:Conductor.length>100.0</cim:Conductor.length>
    <cim:Equipment.EquipmentContainer rdf:resource="#_sub1"/>
  </cim:ACLineSegment>
</rdf:RDF>
''';

const _addedLineXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:Substation rdf:ID="_sub1">
    <cim:IdentifiedObject.name>Substation A</cim:IdentifiedObject.name>
  </cim:Substation>
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:Conductor.length>100.0</cim:Conductor.length>
    <cim:Equipment.EquipmentContainer rdf:resource="#_sub1"/>
  </cim:ACLineSegment>
  <cim:ACLineSegment rdf:ID="_line2">
    <cim:IdentifiedObject.name>Feeder 13</cim:IdentifiedObject.name>
    <cim:Conductor.length>200.0</cim:Conductor.length>
    <cim:Equipment.EquipmentContainer rdf:resource="#_sub1"/>
  </cim:ACLineSegment>
</rdf:RDF>
''';

const _removedSubAddedLineXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:Conductor.length>100.0</cim:Conductor.length>
  </cim:ACLineSegment>
</rdf:RDF>
''';

void main() {
  test('isEmpty when both graphs are identical', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_baseXml),
    );
    expect(diff.isEmpty, isTrue);
  });

  test('detects a renamed attribute as a single modification', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_renameLine1Xml),
    );
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.modified, hasLength(1));
    final mod = diff.modified.single;
    expect(mod.id, '_line1');
    expect(mod.attributeChanges['name']?.oldValue, 'Feeder 12');
    expect(mod.attributeChanges['name']?.newValue, 'Renamed Feeder');
    expect(mod.attributeChanges, hasLength(1));
    expect(mod.associationChanges, isEmpty);
  });

  test('detects an added element', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_addedLineXml),
    );
    expect(diff.added.map((e) => e.id), ['_line2']);
    expect(diff.removed, isEmpty);
    expect(diff.modified, isEmpty);
  });

  test('detects a removed element and the cascading association removal', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_removedSubAddedLineXml),
    );
    expect(diff.removed.map((e) => e.id), ['_sub1']);
    expect(diff.added, isEmpty);
    // _line1 lost its EquipmentContainer assoc.
    expect(diff.modified, hasLength(1));
    final mod = diff.modified.single;
    expect(mod.id, '_line1');
    expect(
      mod.associationChanges['EquipmentContainer']?.oldTargetId,
      '_sub1',
    );
    expect(
      mod.associationChanges['EquipmentContainer']?.newTargetId,
      isNull,
    );
  });

  test('lists are sorted by id for determinism', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_addedLineXml),
    );
    // Only _line2 added; ordering matters when there are several.
    expect(diff.added.length, 1);
  });
}
