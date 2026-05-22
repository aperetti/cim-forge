import 'dart:io';

import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/features/views/view_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Metamodel metamodel;
  late ViewValidator validator;

  setUpAll(() {
    metamodel = SchemaLoader.load(
      File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync(),
    );
    validator = ViewValidator(metamodel);
  });

  test('accepts a well-formed view', () {
    const view = ViewDefinition(
      name: 'Feeders',
      baseClass: 'ACLineSegment',
      columns: [
        ColumnDefinition(path: ['name']),
        ColumnDefinition(path: ['length']),
        ColumnDefinition(path: ['EquipmentContainer', 'name']),
      ],
    );
    expect(validator.validate(view), isEmpty);
  });

  test('rejects unknown base class', () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'Nope',
      columns: [ColumnDefinition(path: ['name'])],
    );
    final issues = validator.validate(view);
    expect(issues, hasLength(1));
    expect(issues.first.path, 'baseClass');
  });

  test('rejects unknown attribute on the base class', () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['nonsuch'])],
    );
    final issues = validator.validate(view);
    expect(issues, hasLength(1));
    expect(issues.first.message, contains('no attribute "nonsuch"'));
  });

  test('rejects unknown association on a column path', () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['NoSuchAssoc', 'name'])],
    );
    final issues = validator.validate(view);
    expect(issues, isNotEmpty);
    expect(issues.first.message, contains('no association "NoSuchAssoc"'));
  });

  test('accepts a reverse-direction composite inclusion', () {
    // EquipmentContainer is declared on Equipment as a 0..1 forward
    // association whose target is EquipmentContainer. Walking it in reverse
    // gives us "children of this Substation."
    const view = ViewDefinition(
      name: 'Subs+Feeders',
      baseClass: 'Substation',
      columns: [ColumnDefinition(path: ['name'])],
      inclusions: [
        CompositeInclusion(
          association: 'EquipmentContainer',
          direction: InclusionDirection.reverse,
          childClass: 'ACLineSegment',
          orderBy: 'name',
          maxCount: 5,
          attributes: ['name', 'length'],
        ),
      ],
    );
    expect(validator.validate(view), isEmpty);
  });

  test('flags an inclusion whose orderBy attribute is missing on child', () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'Substation',
      columns: [ColumnDefinition(path: ['name'])],
      inclusions: [
        CompositeInclusion(
          association: 'EquipmentContainer',
          direction: InclusionDirection.reverse,
          childClass: 'ACLineSegment',
          orderBy: 'no_such_attr',
          maxCount: 5,
          attributes: ['name'],
        ),
      ],
    );
    final issues = validator.validate(view);
    expect(issues, hasLength(1));
    expect(issues.first.path, 'inclusions[0].orderBy');
  });

  test('flags an inclusion whose displayed attribute is missing on child',
      () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'Substation',
      columns: [ColumnDefinition(path: ['name'])],
      inclusions: [
        CompositeInclusion(
          association: 'EquipmentContainer',
          direction: InclusionDirection.reverse,
          childClass: 'ACLineSegment',
          orderBy: 'name',
          maxCount: 5,
          attributes: ['name', 'no_such_attr'],
        ),
      ],
    );
    final issues = validator.validate(view);
    expect(issues, hasLength(1));
    expect(issues.first.path, 'inclusions[0].attributes[1]');
  });

  test('flags an inclusion that names an unrelated association', () {
    const view = ViewDefinition(
      name: 'Bad',
      baseClass: 'Substation',
      columns: [ColumnDefinition(path: ['name'])],
      inclusions: [
        CompositeInclusion(
          association: 'NotAnAssoc',
          direction: InclusionDirection.reverse,
          childClass: 'ACLineSegment',
          orderBy: 'name',
          maxCount: 5,
          attributes: ['name'],
        ),
      ],
    );
    final issues = validator.validate(view);
    expect(issues, isNotEmpty);
    expect(issues.first.path, 'inclusions[0].association');
  });
}
