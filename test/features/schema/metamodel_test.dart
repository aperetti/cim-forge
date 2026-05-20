import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:flutter_test/flutter_test.dart';

Metamodel _buildHierarchy() {
  // IdentifiedObject -> PowerSystemResource -> Equipment -> ACLineSegment.
  return Metamodel(
    classes: {
      'IdentifiedObject': const CimClass(
        name: 'IdentifiedObject',
        ownAttributes: [
          CimAttribute(
            name: 'name',
            dataType: 'String',
            cardinality: Cardinality.optional,
          ),
        ],
      ),
      'PowerSystemResource': const CimClass(
        name: 'PowerSystemResource',
        parent: 'IdentifiedObject',
      ),
      'Equipment': const CimClass(
        name: 'Equipment',
        parent: 'PowerSystemResource',
        ownAssociations: [
          CimAssociation(
            name: 'EquipmentContainer',
            targetClass: 'EquipmentContainer',
            cardinality: Cardinality.optional,
          ),
        ],
      ),
      'ACLineSegment': const CimClass(
        name: 'ACLineSegment',
        parent: 'Equipment',
        ownAttributes: [
          CimAttribute(
            name: 'r',
            dataType: 'Float',
            cardinality: Cardinality.optional,
          ),
        ],
      ),
    },
  );
}

void main() {
  group('Metamodel', () {
    test('attributesOf walks inheritance root-first', () {
      final m = _buildHierarchy();
      final attrs = m.attributesOf('ACLineSegment').map((a) => a.name).toList();
      expect(attrs, ['name', 'r']);
    });

    test('associationsOf walks inheritance root-first', () {
      final m = _buildHierarchy();
      final assocs =
          m.associationsOf('ACLineSegment').map((a) => a.name).toList();
      expect(assocs, ['EquipmentContainer']);
    });

    test('ancestorChain returns root parent first, self last', () {
      final m = _buildHierarchy();
      final chain =
          m.ancestorChain('ACLineSegment').map((c) => c.name).toList();
      expect(chain, [
        'IdentifiedObject',
        'PowerSystemResource',
        'Equipment',
        'ACLineSegment',
      ]);
    });

    test('unknown class throws ArgumentError', () {
      final m = _buildHierarchy();
      expect(() => m.attributesOf('NoSuchClass'), throwsArgumentError);
    });

    test('detects inheritance cycles', () {
      final m = Metamodel(
        classes: {
          'A': const CimClass(name: 'A', parent: 'B'),
          'B': const CimClass(name: 'B', parent: 'A'),
        },
      );
      expect(() => m.attributesOf('A'), throwsStateError);
    });
  });

  group('Cardinality', () {
    test('toString reads naturally', () {
      expect(Cardinality.optional.toString(), '0..1');
      expect(Cardinality.required.toString(), '1..1');
      expect(Cardinality.many.toString(), '0..*');
      expect(Cardinality.oneOrMore.toString(), '1..*');
    });

    test('predicates', () {
      expect(Cardinality.optional.isOptional, isTrue);
      expect(Cardinality.required.isOptional, isFalse);
      expect(Cardinality.many.isUnbounded, isTrue);
      expect(Cardinality.required.isToOne, isTrue);
    });
  });
}
