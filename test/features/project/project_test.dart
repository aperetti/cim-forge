import 'dart:convert';
import 'dart:io';

import 'package:cim_forge/features/project/project.dart';
import 'package:cim_forge/features/project/project_layout.dart';
import 'package:cim_forge/shared/telemetry/spans.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cim_forge_project_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows occasionally retains sqlite file handles briefly.
    }
  });

  test('create writes the on-disk layout and opens the index', () {
    final telemetry = Telemetry(sink: (_) {});
    final project = Project.create(tempDir, telemetry: telemetry)
      ..database.raw.execute('CREATE TABLE smoke (id INTEGER PRIMARY KEY)');
    addTearDown(project.close);

    final layout = ProjectLayout(tempDir);
    expect(File(layout.projectMarkerPath).existsSync(), isTrue);
    expect(Directory(layout.viewsDir).existsSync(), isTrue);
    expect(File(layout.indexPath).existsSync(), isTrue);

    final marker =
        jsonDecode(File(layout.projectMarkerPath).readAsStringSync())
            as Map<String, Object?>;
    expect(marker['formatVersion'], 1);
    expect(marker.containsKey('schemaId'), isTrue);
    expect(marker['createdAt'], isA<String>());

    final gitignore = File(layout.gitignorePath).readAsStringSync();
    for (final entry in projectGitignoreEntries) {
      expect(gitignore, contains(entry), reason: 'missing $entry');
    }

    expect(
      telemetry.recorded.any((s) => s.name == 'project.create'),
      isTrue,
    );
  });

  test('create fails when a project already exists', () {
    Project.create(tempDir, telemetry: Telemetry(sink: (_) {})).close();

    expect(
      () => Project.create(tempDir, telemetry: Telemetry(sink: (_) {})),
      throwsA(isA<ProjectAlreadyExistsException>()),
    );
  });

  test('open round-trips metadata and emits a span', () {
    final createTelemetry = Telemetry(sink: (_) {});
    Project.create(tempDir, telemetry: createTelemetry).close();

    final openTelemetry = Telemetry(sink: (_) {});
    final opened = Project.open(tempDir, telemetry: openTelemetry);
    addTearDown(opened.close);

    expect(opened.metadata.formatVersion, 1);
    expect(opened.metadata.schemaId, isNull);
    expect(
      openTelemetry.recorded.any((s) => s.name == 'project.open'),
      isTrue,
    );
  });

  test('open throws when no project marker is present', () {
    expect(
      () => Project.open(tempDir, telemetry: Telemetry(sink: (_) {})),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });

  test('open throws when the marker is malformed', () {
    final layout = ProjectLayout(tempDir);
    Directory(layout.cimForgeDir).createSync(recursive: true);
    File(layout.projectMarkerPath).writeAsStringSync('not json');

    expect(
      () => Project.open(tempDir, telemetry: Telemetry(sink: (_) {})),
      throwsA(isA<Exception>()),
    );
  });

  test('create extends an existing .gitignore without duplicating entries', () {
    const existing = '# user file\n.env\n';
    File(p.join(tempDir.path, '.gitignore')).writeAsStringSync(existing);

    final project = Project.create(tempDir, telemetry: Telemetry(sink: (_) {}));
    addTearDown(project.close);

    final after = File(p.join(tempDir.path, '.gitignore')).readAsStringSync();
    expect(after, startsWith(existing));
    for (final entry in projectGitignoreEntries) {
      expect(
        '\n$after'.split(RegExp(r'\r?\n')).where((l) => l == entry).length,
        1,
        reason: '$entry should appear exactly once',
      );
    }
  });

  test('open rejects a marker with a future formatVersion', () {
    final layout = ProjectLayout(tempDir);
    Directory(layout.cimForgeDir).createSync(recursive: true);
    File(layout.projectMarkerPath).writeAsStringSync(
      jsonEncode({
        'formatVersion': 999,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'schemaId': null,
      }),
    );

    expect(
      () => Project.open(tempDir, telemetry: Telemetry(sink: (_) {})),
      throwsA(isA<InvalidProjectException>()),
    );
  });
}
