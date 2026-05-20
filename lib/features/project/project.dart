import 'dart:convert';
import 'dart:io';

import 'package:cim_forge/features/git/git_repo.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/project/project_layout.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:cim_forge/shared/telemetry/spans.dart';

const _currentProjectFormatVersion = 1;

class ProjectAlreadyExistsException implements Exception {
  ProjectAlreadyExistsException(this.path);
  final String path;
  @override
  String toString() => 'CIM Forge project already exists at $path';
}

class ProjectNotFoundException implements Exception {
  ProjectNotFoundException(this.path);
  final String path;
  @override
  String toString() => 'No CIM Forge project found at $path';
}

class InvalidProjectException implements Exception {
  InvalidProjectException(this.path, this.reason);
  final String path;
  final String reason;
  @override
  String toString() => 'Invalid CIM Forge project at $path: $reason';
}

class ProjectMetadata {
  const ProjectMetadata({
    required this.formatVersion,
    required this.createdAt,
    required this.schemaId,
  });

  factory ProjectMetadata.fromJson(Map<String, Object?> json, String path) {
    final formatVersion = json['formatVersion'];
    if (formatVersion is! int) {
      throw InvalidProjectException(path, 'missing or invalid formatVersion');
    }
    final createdAt = json['createdAt'];
    if (createdAt is! String) {
      throw InvalidProjectException(path, 'missing or invalid createdAt');
    }
    return ProjectMetadata(
      formatVersion: formatVersion,
      createdAt: DateTime.parse(createdAt),
      schemaId: json['schemaId'] as String?,
    );
  }

  final int formatVersion;
  final DateTime createdAt;
  final String? schemaId;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'schemaId': schemaId,
  };
}

class Project {
  Project._({
    required this.layout,
    required this.metadata,
    required AppDatabase database,
    required Telemetry telemetry,
  }) : _database = database,
       _telemetry = telemetry,
       _released = false;

  /// Creates a new project at [directory]. Fails if a project already exists.
  factory Project.create(Directory directory, {Telemetry? telemetry}) {
    final t = telemetry ?? Telemetry.instance;
    return t.span<Project>('project.create', (tags) {
      tags['path'] = directory.path;
      final layout = ProjectLayout(directory);
      if (File(layout.projectMarkerPath).existsSync()) {
        throw ProjectAlreadyExistsException(layout.projectMarkerPath);
      }

      directory.createSync(recursive: true);
      Directory(layout.cimForgeDir).createSync(recursive: true);
      Directory(layout.viewsDir).createSync(recursive: true);

      final metadata = ProjectMetadata(
        formatVersion: _currentProjectFormatVersion,
        createdAt: DateTime.now().toUtc(),
        schemaId: null,
      );
      File(layout.projectMarkerPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
      );

      _ensureGitignoreEntries(layout);

      final database = AppDatabase.open(
        layout.indexPath,
        migrations: cimIndexMigrations,
      );

      return Project._(
        layout: layout,
        metadata: metadata,
        database: database,
        telemetry: t,
      );
    });
  }

  /// Opens an existing project at [directory].
  factory Project.open(Directory directory, {Telemetry? telemetry}) {
    final t = telemetry ?? Telemetry.instance;
    return t.span<Project>('project.open', (tags) {
      tags['path'] = directory.path;
      final layout = ProjectLayout(directory);
      final markerFile = File(layout.projectMarkerPath);
      if (!markerFile.existsSync()) {
        throw ProjectNotFoundException(directory.path);
      }

      final raw = jsonDecode(markerFile.readAsStringSync());
      if (raw is! Map<String, Object?>) {
        throw InvalidProjectException(
          layout.projectMarkerPath,
          'expected a JSON object',
        );
      }
      final metadata = ProjectMetadata.fromJson(raw, layout.projectMarkerPath);
      if (metadata.formatVersion > _currentProjectFormatVersion) {
        throw InvalidProjectException(
          layout.projectMarkerPath,
          'project format ${metadata.formatVersion} is newer than supported '
          '$_currentProjectFormatVersion',
        );
      }

      final database = AppDatabase.open(
        layout.indexPath,
        migrations: cimIndexMigrations,
      );

      return Project._(
        layout: layout,
        metadata: metadata,
        database: database,
        telemetry: t,
      );
    });
  }

  final ProjectLayout layout;
  final ProjectMetadata metadata;
  AppDatabase _database;
  bool _released;
  final Telemetry _telemetry;
  GitRepo? _gitRepo;

  AppDatabase get database {
    if (_released) {
      throw StateError(
        'Project database is released — call reopenDatabase() first',
      );
    }
    return _database;
  }

  /// True between [releaseDatabase] and [reopenDatabase] — used by the
  /// background indexer handoff. Other code should treat the project as
  /// busy in this state.
  bool get isDatabaseReleased => _released;

  /// Closes the project's SQLite handle so another isolate can take
  /// exclusive access to the file (e.g. `BackgroundIndexer`). Must be
  /// paired with [reopenDatabase] — accessing [database] in between throws.
  void releaseDatabase() {
    if (_released) return;
    _database.close();
    _released = true;
  }

  /// Re-opens the SQLite handle after [releaseDatabase]. Re-applies the
  /// migration list so any schema additions land if the file was edited
  /// by another process in the meantime.
  void reopenDatabase() {
    if (!_released) return;
    _database = AppDatabase.open(
      layout.indexPath,
      migrations: cimIndexMigrations,
    );
    _released = false;
  }

  /// Opens the Git repository under the project root, initializing one if
  /// needed (FR-5.1). The handle is cached for the lifetime of the project.
  GitRepo get gitRepo => _gitRepo ??= GitRepo.openOrInit(layout.rootDirectory);

  void close() {
    _telemetry.span<void>('project.close', (tags) {
      tags['path'] = layout.rootPath;
      _gitRepo?.dispose();
      _gitRepo = null;
      if (!_released) {
        _database.close();
        _released = true;
      }
    });
  }

  static void _ensureGitignoreEntries(ProjectLayout layout) {
    final file = File(layout.gitignorePath);
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final lines = existing.split(RegExp(r'\r?\n')).toSet();

    final missing = projectGitignoreEntries
        .where((entry) => !lines.contains(entry))
        .toList();
    if (missing.isEmpty) return;

    final buffer = StringBuffer(existing);
    if (existing.isNotEmpty && !existing.endsWith('\n')) buffer.write('\n');
    if (existing.isNotEmpty) buffer.write('\n# CIM Forge\n');
    for (final entry in missing) {
      buffer.writeln(entry);
    }
    file.writeAsStringSync(buffer.toString());
  }
}
