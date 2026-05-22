import 'dart:io';

import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/features/views/view_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late ViewStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cim_forge_views_');
    store = ViewStore(viewsDirectory: Directory(p.join(tempDir.path, 'v')));
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {/* Windows: tolerate races */}
  });

  test('listNames returns empty when directory does not exist', () {
    expect(store.listNames(), isEmpty);
  });

  test('save then load round-trips a view', () {
    const view = ViewDefinition(
      name: 'Feeders',
      baseClass: 'ACLineSegment',
      columns: [ColumnDefinition(path: ['name'])],
    );
    store.save(view);
    final reloaded = store.load('Feeders');
    expect(reloaded.name, 'Feeders');
    expect(reloaded.columns.single.path, ['name']);
    expect(store.listNames(), ['Feeders']);
  });

  test('save overwrites an existing view atomically', () {
    store
      ..save(
        const ViewDefinition(
          name: 'A',
          baseClass: 'ACLineSegment',
          columns: [ColumnDefinition(path: ['name'])],
        ),
      )
      ..save(
        const ViewDefinition(
          name: 'A',
          baseClass: 'ACLineSegment',
          columns: [ColumnDefinition(path: ['length'])],
        ),
      );
    expect(store.load('A').columns.single.path, ['length']);
  });

  test('delete removes the file', () {
    store.save(
      const ViewDefinition(
        name: 'A',
        baseClass: 'X',
        columns: [ColumnDefinition(path: ['name'])],
      ),
    );
    expect(store.listNames(), ['A']);
    store.delete('A');
    expect(store.listNames(), isEmpty);
  });

  test('rename moves the file and updates the embedded name', () {
    store
      ..save(
        const ViewDefinition(
          name: 'Old',
          baseClass: 'X',
          columns: [ColumnDefinition(path: ['name'])],
        ),
      )
      ..rename(oldName: 'Old', newName: 'New');
    expect(store.listNames(), ['New']);
    expect(store.load('New').name, 'New');
  });

  test('duplicate copies the view and updates name', () {
    store
      ..save(
        const ViewDefinition(
          name: 'A',
          baseClass: 'X',
          columns: [ColumnDefinition(path: ['name'])],
        ),
      )
      ..duplicate(sourceName: 'A', newName: 'B');
    expect(store.listNames(), ['A', 'B']);
    expect(store.load('B').baseClass, 'X');
  });

  test('rename fails when the target name is taken', () {
    store
      ..save(
        const ViewDefinition(
          name: 'A',
          baseClass: 'X',
          columns: [ColumnDefinition(path: ['name'])],
        ),
      )
      ..save(
        const ViewDefinition(
          name: 'B',
          baseClass: 'X',
          columns: [ColumnDefinition(path: ['name'])],
        ),
      );
    expect(
      () => store.rename(oldName: 'A', newName: 'B'),
      throwsA(isA<ViewStoreException>()),
    );
  });

  test('rejects unsafe names', () {
    expect(ViewStore.isValidName(''), isFalse);
    expect(ViewStore.isValidName('../escape'), isFalse);
    expect(ViewStore.isValidName('with/slash'), isFalse);
    expect(ViewStore.isValidName('a' * 200), isFalse);
    expect(ViewStore.isValidName('My View.1'), isTrue);
  });

  test('load throws ViewStoreException when missing', () {
    expect(
      () => store.load('does-not-exist'),
      throwsA(isA<ViewStoreException>()),
    );
  });
}
