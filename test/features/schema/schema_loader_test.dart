import 'dart:io';

import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Metamodel m;

  setUpAll(() {
    final src = File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync();
    m = SchemaLoader.load(src);
  });

  test('parses class hierarchy with parents resolved', () {
    expect(m.classByName('ACLineSegment')?.parent, 'Conductor');
    expect(m.classByName('Conductor')?.parent, 'ConductingEquipment');
    expect(m.classByName('IdentifiedObject')?.parent, isNull);
  });

  test('inherits attributes through the hierarchy', () {
    final attrs = m.attributesOf('ACLineSegment').map((a) => a.name).toList();
    // Inherited 'name' from IdentifiedObject; 'length' from Conductor; 'r'
    // from ACLineSegment itself.
    expect(attrs, containsAll(['name', 'length', 'r']));
  });

  test('classifies cim:Equipment.EquipmentContainer as an association', () {
    final assocs = m.associationsOf('ACLineSegment');
    expect(
      assocs.any(
        (a) =>
            a.name == 'EquipmentContainer' &&
            a.targetClass == 'EquipmentContainer',
      ),
      isTrue,
    );
  });

  test('detects PhaseCode as an enumeration with members', () {
    final phase = m.enumByName('PhaseCode');
    expect(phase, isNotNull);
    expect(phase!.members, containsAll(['A', 'B', 'C']));
  });

  test('multiplicity is preserved on attributes', () {
    final attr = m
        .attributesOf('IdentifiedObject')
        .singleWhere((a) => a.name == 'name');
    expect(attr.cardinality, Cardinality.optional);
  });
}
