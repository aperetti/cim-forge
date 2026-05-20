import 'dart:io';

import 'package:path/path.dart' as p;

/// Pure path helpers — no IO. Knows the on-disk layout of a CIM Forge project.
///
/// Layout (relative to the repo root):
///   .cimforge/project.json    — committed; project marker + metadata
///   .cimforge/index.sqlite3   — per-clone; gitignored
///   .cimviews/                — committed; view definitions (FR-2.4)
class ProjectLayout {
  ProjectLayout(this.rootDirectory);

  final Directory rootDirectory;

  String get rootPath => rootDirectory.path;

  String get cimForgeDir => p.join(rootPath, '.cimforge');
  String get projectMarkerPath => p.join(cimForgeDir, 'project.json');
  String get indexPath => p.join(cimForgeDir, 'index.sqlite3');
  String get viewsDir => p.join(rootPath, '.cimviews');
  String get gitignorePath => p.join(rootPath, '.gitignore');
}

const projectGitignoreEntries = <String>[
  '/.cimforge/index.sqlite3',
  '/.cimforge/index.sqlite3-journal',
  '/.cimforge/index.sqlite3-wal',
  '/.cimforge/index.sqlite3-shm',
];
