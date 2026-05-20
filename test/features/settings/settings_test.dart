import 'dart:io';

import 'package:cim_forge/features/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSettings', () {
    test('touchRecentProject moves to front and bounds the list', () {
      final s = UserSettings(recentProjects: ['a', 'b'])
        ..touchRecentProject('c')
        ..touchRecentProject('a');
      expect(s.recentProjects, ['a', 'c', 'b']);
    });

    test('touchRecentProject deduplicates entries', () {
      final s = UserSettings(recentProjects: ['x', 'y', 'z'])
        ..touchRecentProject('y');
      expect(s.recentProjects, ['y', 'x', 'z']);
    });

    test('round-trips through JSON', () {
      final s = UserSettings(recentProjects: ['p1', 'p2'])
        ..lastWindow = const WindowGeometry(width: 1280, height: 720);
      final back = UserSettings.fromJson(s.toJson());
      expect(back.recentProjects, ['p1', 'p2']);
      expect(back.lastWindow?.width, 1280);
      expect(back.lastWindow?.height, 720);
    });
  });

  group('SettingsStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cim_forge_settings_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows: tolerate temp cleanup races.
      }
    });

    test('load returns defaults when no file exists', () async {
      final store = SettingsStore(directory: tempDir);
      final settings = await store.load();
      expect(settings.recentProjects, isEmpty);
      expect(settings.lastWindow, isNull);
    });

    test('save then load round-trips', () async {
      final store = SettingsStore(directory: tempDir);
      final s = UserSettings(recentProjects: ['/path/to/a', '/path/to/b'])
        ..lastWindow = const WindowGeometry(width: 1600, height: 900);
      await store.save(s);

      final reloaded = await store.load();
      expect(reloaded.recentProjects, ['/path/to/a', '/path/to/b']);
      expect(reloaded.lastWindow?.width, 1600);
      expect(reloaded.lastWindow?.height, 900);
    });

    test('load recovers from a corrupt settings file', () async {
      File('${tempDir.path}/settings.json').writeAsStringSync('not json');
      final store = SettingsStore(directory: tempDir);
      final settings = await store.load();
      expect(settings.recentProjects, isEmpty);
    });
  });
}
