import 'dart:io';

import 'package:cim_forge/features/editing/edit_validator.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EditValidator validator;

  setUpAll(() {
    final graph = ObjectGraph.parse(
      File('test/fixtures/cim/sample.xml').readAsStringSync(),
    );
    final metamodel = SchemaLoader.load(
      File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync(),
    );
    validator = EditValidator(metamodel: metamodel, graph: graph);
  });

  group('SetAttributeValueOp', () {
    test('accepts a valid string attribute change', () {
      final issues = validator.validate(
        const SetAttributeValueOp(
          elementId: '_line1',
          attributeName: 'name',
          newValue: 'Renamed',
          oldValue: 'Feeder 12',
        ),
      );
      expect(issues, isEmpty);
    });

    test('accepts a valid float attribute change', () {
      final issues = validator.validate(
        const SetAttributeValueOp(
          elementId: '_line1',
          attributeName: 'r',
          newValue: '0.021',
          oldValue: '0.013',
        ),
      );
      expect(issues, isEmpty);
    });

    test('rejects a non-numeric float attribute', () {
      final issues = validator.validate(
        const SetAttributeValueOp(
          elementId: '_line1',
          attributeName: 'r',
          newValue: 'not-a-number',
          oldValue: '0.013',
        ),
      );
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('floating-point'));
    });

    test('rejects an unknown attribute on the class', () {
      final issues = validator.validate(
        const SetAttributeValueOp(
          elementId: '_line1',
          attributeName: 'nope',
          newValue: 'x',
          oldValue: 'y',
        ),
      );
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('no attribute "nope"'));
    });

    test('rejects an unknown element id', () {
      final issues = validator.validate(
        const SetAttributeValueOp(
          elementId: '_does_not_exist',
          attributeName: 'name',
          newValue: 'x',
          oldValue: 'y',
        ),
      );
      expect(issues, isNotEmpty);
    });
  });

  group('SetAssociationTargetOp', () {
    test('accepts retargeting an association to a valid Substation', () {
      final issues = validator.validate(
        const SetAssociationTargetOp(
          elementId: '_line1',
          associationName: 'EquipmentContainer',
          newTargetId: '_sub1',
          oldTargetId: '_sub1',
        ),
      );
      expect(issues, isEmpty);
    });

    test('rejects retargeting to a non-existent element', () {
      final issues = validator.validate(
        const SetAssociationTargetOp(
          elementId: '_line1',
          associationName: 'EquipmentContainer',
          newTargetId: '_ghost',
          oldTargetId: '_sub1',
        ),
      );
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('does not exist'));
    });

    test('rejects retargeting to an element of the wrong class', () {
      final issues = validator.validate(
        const SetAssociationTargetOp(
          elementId: '_line1',
          associationName: 'EquipmentContainer',
          newTargetId: '_line2',
          oldTargetId: '_sub1',
        ),
      );
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('expects EquipmentContainer'));
    });
  });

  group('CompositeOp', () {
    test('reports issues from every child', () {
      final issues = validator.validate(
        const CompositeOp(
          label: 'rename batch',
          children: [
            SetAttributeValueOp(
              elementId: '_line1',
              attributeName: 'name',
              newValue: 'OK',
              oldValue: '?',
            ),
            SetAttributeValueOp(
              elementId: '_line1',
              attributeName: 'r',
              newValue: 'not-numeric',
              oldValue: '0',
            ),
          ],
        ),
      );
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('floating-point'));
    });
  });
}
