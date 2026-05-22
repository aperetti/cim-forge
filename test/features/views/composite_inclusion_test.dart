import 'package:cim_forge/features/views/view_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompositeInclusion JSON', () {
    test('round-trips a full inclusion', () {
      const inclusion = CompositeInclusion(
        association: 'EquipmentContainer',
        direction: InclusionDirection.reverse,
        childClass: 'ACLineSegment',
        orderBy: 'name',
        maxCount: 5,
        attributes: ['name', 'length'],
        descending: true,
        label: 'Feeders',
      );
      final back = CompositeInclusion.fromJson(inclusion.toJson());
      expect(back, inclusion);
    });

    test('preserves default descending=false', () {
      const inclusion = CompositeInclusion(
        association: 'r',
        direction: InclusionDirection.forward,
        childClass: 'C',
        orderBy: 'k',
        maxCount: 3,
        attributes: ['a'],
      );
      final back = CompositeInclusion.fromJson(inclusion.toJson());
      expect(back.descending, isFalse);
    });

    test('rejects maxCount <= 0', () {
      expect(
        () => CompositeInclusion.fromJson(const <String, Object?>{
          'association': 'a',
          'direction': 'forward',
          'childClass': 'c',
          'orderBy': 'k',
          'maxCount': 0,
          'attributes': <String>[],
        }),
        throwsFormatException,
      );
    });

    test('rejects unknown direction', () {
      expect(
        () => CompositeInclusion.fromJson(const <String, Object?>{
          'association': 'a',
          'direction': 'sideways',
          'childClass': 'c',
          'orderBy': 'k',
          'maxCount': 2,
          'attributes': <String>[],
        }),
        throwsFormatException,
      );
    });
  });

  group('ViewDefinition with inclusions', () {
    test('round-trips inclusions through JSON', () {
      const view = ViewDefinition(
        name: 'Substations w/ Feeders',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
        inclusions: [
          CompositeInclusion(
            association: 'EquipmentContainer',
            direction: InclusionDirection.reverse,
            childClass: 'ACLineSegment',
            orderBy: 'name',
            maxCount: 3,
            attributes: ['name', 'length'],
          ),
        ],
      );
      final back = ViewDefinition.fromJson(view.toJson());
      expect(back.inclusions, hasLength(1));
      expect(back.inclusions.single.maxCount, 3);
      expect(back.inclusions.single.attributes, ['name', 'length']);
    });

    test('omits inclusions key when empty', () {
      const view = ViewDefinition(
        name: 'NoInclusions',
        baseClass: 'X',
        columns: [ColumnDefinition(path: ['name'])],
      );
      expect(view.toJson().containsKey('inclusions'), isFalse);
    });
  });
}
