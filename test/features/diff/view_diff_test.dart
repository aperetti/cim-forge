import 'package:cim_forge/features/diff/semantic_diff.dart';
import 'package:cim_forge/features/diff/view_diff.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/views/view_definition.dart';
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
  </cim:ACLineSegment>
</rdf:RDF>
''';

const _renamedXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:Substation rdf:ID="_sub1">
    <cim:IdentifiedObject.name>Substation A</cim:IdentifiedObject.name>
  </cim:Substation>
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Renamed</cim:IdentifiedObject.name>
    <cim:Conductor.length>100.0</cim:Conductor.length>
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
  </cim:ACLineSegment>
  <cim:ACLineSegment rdf:ID="_line2">
    <cim:IdentifiedObject.name>New Feeder</cim:IdentifiedObject.name>
    <cim:Conductor.length>200.0</cim:Conductor.length>
  </cim:ACLineSegment>
</rdf:RDF>
''';

const _feederView = ViewDefinition(
  name: 'Feeders',
  baseClass: 'ACLineSegment',
  columns: [
    ColumnDefinition(path: ['name']),
    ColumnDefinition(path: ['length']),
  ],
);

void main() {
  test('isEmpty when the SemanticDiff is empty', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_baseXml),
    );
    final projected = ViewDiff.project(diff, _feederView);
    expect(projected.isEmpty, isTrue);
  });

  test('projects a single attribute change to a one-cell row diff', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_renamedXml),
    );
    final projected = ViewDiff.project(diff, _feederView);
    expect(projected.rowsAdded, isEmpty);
    expect(projected.rowsRemoved, isEmpty);
    expect(projected.rowsModified, hasLength(1));
    final row = projected.rowsModified.single;
    expect(row.elementId, '_line1');
    expect(row.cellChanges, hasLength(1));
    final change = row.cellChanges[0]!;
    expect(change.oldValue, 'Feeder 12');
    expect(change.newValue, 'Renamed');
  });

  test('reports a new base-class element as a row addition', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(_addedLineXml),
    );
    final projected = ViewDiff.project(diff, _feederView);
    expect(projected.rowsAdded.map((e) => e.id), ['_line2']);
  });

  test('ignores changes to elements of other classes', () {
    final diff = SemanticDiff.between(
      ObjectGraph.parse(_baseXml),
      ObjectGraph.parse(
        _baseXml.replaceFirst('Substation A', 'Renamed Sub'),
      ),
    );
    final projected = ViewDiff.project(diff, _feederView);
    expect(projected.isEmpty, isTrue,
        reason: 'Substation rename is invisible to a feeder view');
  });
}
