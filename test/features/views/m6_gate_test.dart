import 'dart:io';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/features/views/view_validator.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ctx {
  _Ctx({
    required this.db,
    required this.engine,
    required this.metamodel,
    required this.source,
    required this.controller,
  });
  final AppDatabase db;
  final QueryEngine engine;
  final Metamodel metamodel;
  final String source;
  final EditController controller;
}

_Ctx _buildCompositeContext() {
  final db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
  final source = File('test/fixtures/cim/sample_composite.xml')
      .readAsStringSync();
  final graph = ObjectGraph.parse(source);
  final fileId = Indexer(database: db).indexGraph(
    filePath: 'sample_composite.xml',
    contentHash: null,
    graph: graph,
  );
  final metamodel = SchemaLoader.load(
    File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync(),
  );
  final engine = QueryEngine(metamodel: metamodel);
  final controller = EditController(
    graph: graph,
    metamodel: metamodel,
    database: db,
    fileId: fileId,
  );
  return _Ctx(
    db: db,
    engine: engine,
    metamodel: metamodel,
    source: source,
    controller: controller,
  );
}

void main() {
  group('M6 gate — composite view expansion + overflow', () {
    test('substation row exposes maxCount slots in order with overflow flag',
        () {
      final ctx = _buildCompositeContext();
      addTearDown(ctx.controller.dispose);
      addTearDown(ctx.db.close);

      const view = ViewDefinition(
        name: 'Subs + first 2 feeders',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
        inclusions: [
          CompositeInclusion(
            association: 'EquipmentContainer',
            direction: InclusionDirection.reverse,
            childClass: 'ACLineSegment',
            orderBy: 'name',
            maxCount: 2,
            attributes: ['name', 'length'],
          ),
        ],
      );

      final rows = ctx.engine.execute(ctx.db, view, limit: 10, offset: 0);
      expect(rows, hasLength(1));
      final substation = rows.single;
      expect(substation.elementId, '_sub1');
      expect(substation.values.single, 'Substation A');

      expect(substation.slots, hasLength(1));
      final slotData = substation.slots.single;
      expect(slotData.slots, hasLength(2));
      expect(slotData.overflow, isTrue,
          reason: 'fixture has 4 feeders; maxCount=2 → overflow');

      // Slots ordered alphabetically by name: Feeder A first, Feeder B second.
      expect(slotData.slots[0]!.childId, '_lineA');
      expect(slotData.slots[0]!.values, ['Feeder A', '100.0']);
      expect(slotData.slots[1]!.childId, '_lineB');
      expect(slotData.slots[1]!.values, ['Feeder B', '200.0']);
    });

    test('descending sort flips slot order', () {
      final ctx = _buildCompositeContext();
      addTearDown(ctx.controller.dispose);
      addTearDown(ctx.db.close);

      const view = ViewDefinition(
        name: 'Subs + last 2 feeders',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
        inclusions: [
          CompositeInclusion(
            association: 'EquipmentContainer',
            direction: InclusionDirection.reverse,
            childClass: 'ACLineSegment',
            orderBy: 'name',
            maxCount: 2,
            attributes: ['name'],
            descending: true,
          ),
        ],
      );
      final rows = ctx.engine.execute(ctx.db, view, limit: 10, offset: 0);
      final slots = rows.single.slots.single;
      expect(slots.slots[0]!.values.single, 'Feeder D');
      expect(slots.slots[1]!.values.single, 'Feeder C');
    });

    test('overflow=false when child count ≤ maxCount', () {
      final ctx = _buildCompositeContext();
      addTearDown(ctx.controller.dispose);
      addTearDown(ctx.db.close);

      const view = ViewDefinition(
        name: 'Subs + all 4 feeders',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
        inclusions: [
          CompositeInclusion(
            association: 'EquipmentContainer',
            direction: InclusionDirection.reverse,
            childClass: 'ACLineSegment',
            orderBy: 'name',
            maxCount: 8,
            attributes: ['name'],
          ),
        ],
      );
      final rows = ctx.engine.execute(ctx.db, view, limit: 10, offset: 0);
      final slots = rows.single.slots.single;
      expect(slots.overflow, isFalse);
      expect(
        slots.slots.where((s) => s != null).map((s) => s!.values.single),
        ['Feeder A', 'Feeder B', 'Feeder C', 'Feeder D'],
      );
    });
  });

  group('M6 gate — composite write round-trip', () {
    test('editing a slot attribute mutates the right child element and '
        'survives parse → patch → reparse', () {
      final ctx = _buildCompositeContext();
      addTearDown(ctx.controller.dispose);
      addTearDown(ctx.db.close);

      // Rename Feeder B via an op against _lineB — exactly what the grid's
      // edit-routing layer will do for slot cells.
      ctx.controller.apply(
        const SetAttributeValueOp(
          elementId: '_lineB',
          attributeName: 'name',
          newValue: 'Renamed B',
          oldValue: 'Feeder B',
        ),
      );

      // Slot ordering uses the orderBy attribute (name). Renamed values
      // would reshuffle the slots — assert via element id and live value
      // rather than position.
      expect(
        ctx.controller.currentAttribute('_lineB', 'name'),
        'Renamed B',
      );

      final patched = ctx.controller.renderPatchedSource();
      final reparsed = ObjectGraph.parse(patched);
      expect(
        reparsed.elementById('_lineB')?.attribute('name')?.value,
        'Renamed B',
      );
      // Other elements untouched.
      expect(
        reparsed.elementById('_lineA')?.attribute('name')?.value,
        'Feeder A',
      );
      expect(
        reparsed.elementById('_sub1')?.attribute('name')?.value,
        'Substation A',
      );
    });
  });

  group('M6 gate — view validation against the schema', () {
    test('validator reports issues for inclusions referencing missing attrs',
        () {
      final ctx = _buildCompositeContext();
      addTearDown(ctx.controller.dispose);
      addTearDown(ctx.db.close);

      final validator = ViewValidator(ctx.metamodel);
      const bad = ViewDefinition(
        name: 'broken',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
        inclusions: [
          CompositeInclusion(
            association: 'EquipmentContainer',
            direction: InclusionDirection.reverse,
            childClass: 'ACLineSegment',
            orderBy: 'name',
            maxCount: 2,
            attributes: ['name', 'voltage_not_in_schema'],
          ),
        ],
      );
      final issues = validator.validate(bad);
      expect(issues, hasLength(1));
      expect(issues.single.path, 'inclusions[0].attributes[1]');
    });
  });
}
