import 'dart:io';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/query_grid_source.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late QueryEngine engine;
  late EditController controller;

  setUp(() {
    db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
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
    engine = QueryEngine(metamodel: metamodel);
    controller = EditController(
      graph: graph,
      metamodel: metamodel,
      database: db,
      fileId: fileId,
    );
  });

  tearDown(() {
    controller.dispose();
    db.close();
  });

  test('exposes base + slot columns flattened in the expected order',
      () async {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'composite',
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
      ),
      editController: controller,
    );
    addTearDown(source.dispose);

    // 1 base column + 2 slots * 2 attributes = 5 columns.
    expect(source.columnCount, 5);
    expect(source.columnAt(0).header, 'name');
    // Slot 1 attributes (header pattern: "<label> · #<slot> · <attr>").
    expect(source.columnAt(1).header, contains('#1'));
    expect(source.columnAt(1).header, contains('name'));
    expect(source.columnAt(2).header, contains('length'));
    expect(source.columnAt(3).header, contains('#2'));

    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Substation row → base name, then slot 1 name, slot 1 length, slot 2…
    expect(source.cellAt(0, 0), 'Substation A');
    expect(source.cellAt(0, 1), 'Feeder A');
    expect(source.cellAt(0, 2), '100.0');
    expect(source.cellAt(0, 3), 'Feeder B');
    expect(source.cellAt(0, 4), '200.0');

    expect(source.isInclusionOverflowing(0, 0), isTrue);
  });

  test('cellEditor on a slot column routes edits to the child element',
      () async {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'composite',
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
          ),
        ],
      ),
      editController: controller,
    );
    addTearDown(source.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Column 1 = inclusion 0, slot 0, attr 'name' → backing element _lineA.
    final editor = source.cellEditor(0, 1);
    expect(editor, isNotNull);
    await editor!('Renamed A');

    // Edit lands on _lineA, NOT the Substation.
    expect(controller.currentAttribute('_lineA', 'name'), 'Renamed A');
    expect(controller.currentAttribute('_sub1', 'name'), 'Substation A');
  });

  test('cellEditor returns null for an empty slot (no child to address)',
      () async {
    final source = QueryGridSource(
      database: db,
      engine: engine,
      view: const ViewDefinition(
        name: 'sparseComposite',
        baseClass: 'Substation',
        columns: [ColumnDefinition(path: ['name'])],
        inclusions: [
          CompositeInclusion(
            association: 'EquipmentContainer',
            direction: InclusionDirection.reverse,
            childClass: 'ACLineSegment',
            orderBy: 'name',
            maxCount: 10,
            attributes: ['name'],
          ),
        ],
      ),
      editController: controller,
    );
    addTearDown(source.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 5));

    // The fixture has 4 children; slot 5+ are empty → no editor.
    final emptySlotEditor = source.cellEditor(0, 1 + 5);
    expect(emptySlotEditor, isNull);
  });
}
