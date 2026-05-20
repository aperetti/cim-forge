// Spike TR-9.2 — libgit2 on Windows via git2dart prebuilt binaries.
//
// Questions:
//   1. Does git2dart load `libgit2.dll` from the `git2dart_binaries` package
//      without us building libgit2 from source on Windows? (TR-9.2)
//   2. Can we drive the Git operations we need: init, stage, commit, branch,
//      and tree-to-tree diff? Diff is the engine behind FR-6.1 (native XML diff
//      between commits); the rest cover FA-5 (open/init, commit, branch).
//   3. Does the prebuilt libgit2 advertise HTTPS / SSH features we need for
//      FR-5.5 / FR-5.7?
//
// Runs under `flutter test` because `git2dart_binaries` transitively imports
// `package:flutter/services.dart` (its Android SSL helper). On Windows desktop
// the helper is never called, but the import forces a Flutter runner.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

const xmlV1 = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:Conductor.length>1234.5</cim:Conductor.length>
  </cim:ACLineSegment>
</rdf:RDF>
''';

// Identical to v1 except for the length value — mirrors what a surgical patch
// from spike TR-9.1 would produce. We want the diff to be a single-line change.
const xmlV2 = '''
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:cim="http://iec.ch/TC57/CIM100#">
  <cim:ACLineSegment rdf:ID="_line1">
    <cim:IdentifiedObject.name>Feeder 12</cim:IdentifiedObject.name>
    <cim:Conductor.length>9999.9</cim:Conductor.length>
  </cim:ACLineSegment>
</rdf:RDF>
''';

void main() {
  test('prebuilt libgit2 loads on Windows and supports init/commit/diff/branch',
      () {
    final version = Libgit2.version;
    final features = Libgit2.features;
    printOnFailure('libgit2 version: $version');
    printOnFailure('features: $features');
    expect(version, isNotEmpty);
    // Smoke-print so the spike output is informative even on PASS.
    // ignore: avoid_print
    print('libgit2 version: $version');
    // ignore: avoid_print
    print('features:        $features');

    final tmp = Directory.systemTemp.createTempSync('cim_forge_libgit2_spike_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final repo = Repository.init(path: tmp.path);
    repo.config['user.name'] = 'CIM Forge Spike';
    repo.config['user.email'] = 'spike@cim-forge.local';

    const fileName = 'model.xml';
    final filePath = p.join(repo.workdir, fileName);
    final sig = repo.defaultSignature;

    // Initial commit — no parent, so use Commit.create directly.
    File(filePath).writeAsStringSync(xmlV1);
    repo.index.add(fileName);
    repo.index.write();
    final firstTreeOid = repo.index.writeTree();
    final firstOid = Commit.create(
      repo: repo,
      updateRef: 'HEAD',
      author: sig,
      committer: sig,
      message: 'initial commit\n',
      tree: Tree.lookup(repo: repo, oid: firstTreeOid),
      parents: const [],
    );

    // Second commit — HEAD now exists, extension method works.
    File(filePath).writeAsStringSync(xmlV2);
    final secondOid = repo.createCommitOnHead(
      [fileName],
      sig,
      sig,
      'change Conductor.length\n',
    );

    // Tree-to-tree diff — the engine behind FR-6.1 (text-level XML diff).
    final oldTree = Commit.lookup(repo: repo, oid: firstOid).tree;
    final newTree = Commit.lookup(repo: repo, oid: secondOid).tree;
    final diff = Diff.treeToTree(
      repo: repo,
      oldTree: oldTree,
      newTree: newTree,
    );
    // ignore: avoid_print
    print('\n=== Diff (text patch) ===\n${diff.patch}');

    expect(
      diff.patch,
      allOf(
        contains('-    <cim:Conductor.length>1234.5'),
        contains('+    <cim:Conductor.length>9999.9'),
      ),
      reason: 'tree-to-tree diff must surface the changed XML line',
    );

    // Branch off the first commit (FR-5.3).
    final branch = Branch.create(
      repo: repo,
      name: 'spike-branch',
      target: Commit.lookup(repo: repo, oid: firstOid),
    );
    final branchNames = repo.branches.map((b) => b.name).toSet();
    expect(branchNames, contains(branch.name));
  });
}
