import 'dart:io';

import 'package:cim_forge/features/git/git_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as g;
import 'package:path/path.dart' as p;

const String _sampleFixturePath = 'test/fixtures/cim/sample.xml';

Directory _newTempDir(String prefix) =>
    Directory.systemTemp.createTempSync(prefix);

void _writeFile(Directory dir, String name, String content) =>
    File(p.join(dir.path, name)).writeAsStringSync(content);

String _readFile(Directory dir, String name) =>
    File(p.join(dir.path, name)).readAsStringSync();

/// Returns the file:// URL form of [dir] suitable for libgit2 remotes.
/// On Windows the path is `C:\foo\bar`; URI conversion normalises slashes
/// and adds the file:// scheme.
String _fileUrl(Directory dir) => Uri.file(dir.path).toString();

void main() {
  group('M8 gate — file:// remote clone / push / pull round-trip', () {
    test('clone, push, second clone, fetch+pull (fast-forward) all wire up',
        () {
      final upstreamDir = _newTempDir('cim_m8_upstream_');
      final workDir = _newTempDir('cim_m8_work_');
      final mirrorDir = _newTempDir('cim_m8_mirror_');
      addTearDown(() {
        for (final d in [upstreamDir, workDir, mirrorDir]) {
          try {
            d.deleteSync(recursive: true);
          } on FileSystemException {
            // Windows holds .pack file handles briefly after GC.
          }
        }
      });

      // 1. Bare upstream repo.
      g.Repository.init(path: upstreamDir.path, bare: true);

      // 2. Working repo with an initial commit, push to upstream.
      _writeFile(
        workDir,
        'model.xml',
        File(_sampleFixturePath).readAsStringSync(),
      );
      final work = GitRepo.openOrInit(workDir)
        ..ensureSignature(
          name: 'CIM Forge Gate',
          email: 'gate@cim-forge.local',
        );
      addTearDown(work.dispose);
      work
        ..stage('model.xml')
        ..commit('initial')
        ..addRemote(name: 'origin', url: _fileUrl(upstreamDir))
        ..push('origin');
      final firstSha = work.head()!.sha;

      // 3. Second clone from the same upstream — should see the commit.
      final mirror = GitRepo.clone(
        url: _fileUrl(upstreamDir),
        directory: mirrorDir,
      );
      addTearDown(mirror.dispose);
      expect(mirror.head()?.sha, firstSha);
      expect(_readFile(mirrorDir, 'model.xml'), contains('Feeder 12'));

      // 4. Make a second commit in the work repo and push.
      _writeFile(
        workDir,
        'model.xml',
        File(_sampleFixturePath)
            .readAsStringSync()
            .replaceAll('Feeder 12', 'Renamed Feeder'),
      );
      work
        ..stage('model.xml')
        ..commit('rename feeder')
        ..push('origin');
      final secondSha = work.head()!.sha;

      // 5. Mirror fetches + pulls (fast-forward) and now sees the new commit.
      final pullResult = mirror.pull('origin');
      expect(pullResult.kind, PullKind.fastForwarded);
      expect(pullResult.fastForwardedTo, secondSha);
      expect(mirror.head()?.sha, secondSha);
      expect(_readFile(mirrorDir, 'model.xml'), contains('Renamed Feeder'));
    });

    test('pull on an up-to-date branch is a no-op', () {
      final upstreamDir = _newTempDir('cim_m8_upstream_');
      final workDir = _newTempDir('cim_m8_work_');
      addTearDown(() {
        for (final d in [upstreamDir, workDir]) {
          try {
            d.deleteSync(recursive: true);
          } on FileSystemException {
            // Windows .pack handle race.
          }
        }
      });

      g.Repository.init(path: upstreamDir.path, bare: true);
      _writeFile(workDir, 'a.txt', 'hello\n');
      final work = GitRepo.openOrInit(workDir)
        ..ensureSignature(
          name: 'Gate',
          email: 'gate@cim-forge.local',
        );
      addTearDown(work.dispose);
      work
        ..stage('a.txt')
        ..commit('initial')
        ..addRemote(name: 'origin', url: _fileUrl(upstreamDir))
        ..push('origin');

      final result = work.pull('origin');
      expect(result.kind, PullKind.upToDate);
    });

    test('listRemotes returns the configured remotes', () {
      final dir = _newTempDir('cim_m8_remotes_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {/* Windows */}
      });
      final repo = GitRepo.openOrInit(dir);
      addTearDown(repo.dispose);
      repo
        ..addRemote(name: 'origin', url: 'https://example.test/repo.git')
        ..addRemote(name: 'fork', url: 'git@example.test:fork/repo.git');
      final remotes = repo.listRemotes();
      expect(remotes.map((r) => r.name), unorderedEquals(['origin', 'fork']));
    });
  });
}
