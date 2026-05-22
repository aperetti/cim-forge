import 'dart:io';

import 'package:cim_forge/features/diff/semantic_diff.dart';
import 'package:cim_forge/features/git/git_repo.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/xml_patch/canonical_serializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _sampleFixturePath = 'test/fixtures/cim/sample.xml';

Directory _newTempRepo() =>
    Directory.systemTemp.createTempSync('cim_forge_m7_gate_');

String _fileAt(Directory dir, String name) =>
    File(p.join(dir.path, name)).readAsStringSync();

void _writeFile(Directory dir, String name, String content) =>
    File(p.join(dir.path, name)).writeAsStringSync(content);

void main() {
  group('M7 gate — merge conflict surfacing at element level (FR-6.4)', () {
    test('two branches editing the same attribute produce a libgit2 conflict, '
        'and SemanticDiff names the divergent element', () {
      final repoDir = _newTempRepo();
      addTearDown(() {
        try {
          repoDir.deleteSync(recursive: true);
        } on FileSystemException {/* tolerate Windows */}
      });

      final fixture = File(_sampleFixturePath).readAsStringSync();
      _writeFile(repoDir, 'model.xml', fixture);

      final git = GitRepo.openOrInit(repoDir)
        ..ensureSignature(
          name: 'CIM Forge Gate',
          email: 'gate@cim-forge.local',
        );
      addTearDown(git.dispose);
      git
        ..stage('model.xml')
        ..commit('initial');
      final initialSha = git.head()!.sha;
      final mainBranch = git.currentBranch()!;

      // Branch "feature" renames Feeder 12 → Renamed-by-feature.
      git
        ..createBranch(name: 'feature', fromSha: initialSha)
        ..checkoutBranch('feature');
      _writeFile(
        repoDir,
        'model.xml',
        fixture.replaceAll(
          'Feeder 12',
          'Renamed-by-feature',
        ),
      );
      git
        ..stage('model.xml')
        ..commit('feature: rename')
        ..checkoutBranch(mainBranch);

      // Back on main, rename Feeder 12 → Renamed-by-main differently.
      _writeFile(
        repoDir,
        'model.xml',
        fixture.replaceAll(
          'Feeder 12',
          'Renamed-by-main',
        ),
      );
      // Merge feature into main → conflict.
      git
        ..stage('model.xml')
        ..commit('main: rename')
        ..mergeBranch('feature');
      final conflicts = git.conflicts();
      expect(
        conflicts,
        hasLength(1),
        reason: 'a divergent edit on the same line must conflict',
      );
      final conflict = conflicts.single;
      expect(conflict.path, 'model.xml');
      expect(conflict.ancestorSha, isNotNull);
      expect(conflict.ourSha, isNotNull);
      expect(conflict.theirSha, isNotNull);

      // Project the conflict to element level via SemanticDiff(ours, theirs).
      final oursXml = git.readBlob(conflict.ourSha!);
      final theirsXml = git.readBlob(conflict.theirSha!);
      final diff = SemanticDiff.between(
        ObjectGraph.parse(oursXml),
        ObjectGraph.parse(theirsXml),
      );

      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
      expect(diff.modified, hasLength(1));
      final mod = diff.modified.single;
      expect(mod.id, '_line1',
          reason: 'element-level surfacing: _line1 is the divergent element');
      expect(mod.attributeChanges['name']?.oldValue, 'Renamed-by-main');
      expect(mod.attributeChanges['name']?.newValue, 'Renamed-by-feature');

      // Clean up the in-flight merge so the temp dir delete succeeds.
      git.abortMerge();
    });

    test('non-conflicting edits on different elements merge cleanly', () {
      final repoDir = _newTempRepo();
      addTearDown(() {
        try {
          repoDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows: tolerate races releasing .pack file handles.
        }
      });

      final fixture = File(_sampleFixturePath).readAsStringSync();
      _writeFile(repoDir, 'model.xml', fixture);

      final git = GitRepo.openOrInit(repoDir)
        ..ensureSignature(
          name: 'CIM Forge Gate',
          email: 'gate@cim-forge.local',
        );
      addTearDown(git.dispose);
      git
        ..stage('model.xml')
        ..commit('initial');
      final initialSha = git.head()!.sha;
      final mainBranch = git.currentBranch()!;

      git
        ..createBranch(name: 'feature', fromSha: initialSha)
        ..checkoutBranch('feature');
      // Feature edits _line2's length.
      _writeFile(
        repoDir,
        'model.xml',
        fixture.replaceAll('987.0', '9999.0'),
      );
      git
        ..stage('model.xml')
        ..commit('feature: change line2 length')
        ..checkoutBranch(mainBranch);

      // Main edits _line1's length (far from feature's change).
      _writeFile(
        repoDir,
        'model.xml',
        fixture.replaceAll('1234.5', '5678.9'),
      );
      git
        ..stage('model.xml')
        ..commit('main: change line1 length')
        ..mergeBranch('feature');
      expect(
        git.conflicts(),
        isEmpty,
        reason: 'edits on different lines must merge cleanly',
      );
      // The working tree carries both changes after a clean text merge.
      final merged = _fileAt(repoDir, 'model.xml');
      expect(merged, contains('5678.9'));
      expect(merged, contains('9999.0'));
      git.abortMerge();
    });
  });

  group('M7 gate — normalize round-trip (FR-4.3)', () {
    test('canonicalize → parse yields an element-equivalent graph', () {
      final source = File(_sampleFixturePath).readAsStringSync();
      final original = ObjectGraph.parse(source);
      final canonical =
          const CanonicalSerializer().serialize(original);
      final reparsed = ObjectGraph.parse(canonical);

      expect(reparsed.elementCount, original.elementCount);
      for (final el in original.elements) {
        final back = reparsed.elementById(el.id)!;
        expect(back.className, el.className);
        for (final a in el.attributes) {
          expect(back.attribute(a.shortName)?.value, a.value);
        }
        for (final a in el.associations) {
          expect(back.association(a.shortName)?.targetId, a.targetId);
        }
      }
    });
  });
}
