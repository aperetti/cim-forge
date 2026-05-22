import 'dart:io';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/editing/operations.dart';
import 'package:cim_forge/features/git/git_repo.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _sampleFixturePath = 'test/fixtures/cim/sample.xml';
const String _schemaFixturePath = 'test/fixtures/cim/sample_schema.rdfs';

Directory _newTempRepo() =>
    Directory.systemTemp.createTempSync('cim_forge_m5_gate_');

/// Returns the number of lines in [unifiedDiff] that begin with `+` or `-`
/// (excluding the file headers `+++` / `---`).
int countChangedLines(String unifiedDiff) {
  var count = 0;
  for (final line in unifiedDiff.split('\n')) {
    if (line.startsWith('+++') || line.startsWith('---')) continue;
    if (line.startsWith('+') || line.startsWith('-')) count++;
  }
  return count;
}

void main() {
  group('M5 gate — surgical edit → libgit2 diff is minimal', () {
    test('a single SetAttributeValueOp produces a 2-line tree-to-tree diff',
        () async {
      final repoDir = _newTempRepo();
      addTearDown(() {
        try {
          repoDir.deleteSync(recursive: true);
        } on FileSystemException {/* tolerate Windows races */}
      });

      // Seed the repo with the CIM Forge sample fixture.
      final fixtureSource = File(_sampleFixturePath).readAsStringSync();
      final modelPath = p.join(repoDir.path, 'model.xml');
      File(modelPath).writeAsStringSync(fixtureSource);

      final git = GitRepo.openOrInit(repoDir)
        ..ensureSignature(
          name: 'CIM Forge Gate',
          email: 'gate@cim-forge.local',
        );
      addTearDown(git.dispose);
      git
        ..stage('model.xml')
        ..commit('initial');
      final firstSha = git.head()!.sha;

      // Drive a single surgical edit through the EditController, exactly
      // as the production UI would.
      final db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
      addTearDown(db.close);
      final graph = ObjectGraph.parse(fixtureSource);
      final fileId = Indexer(database: db).indexGraph(
        filePath: modelPath,
        contentHash: null,
        graph: graph,
      );
      final metamodel = SchemaLoader.load(
        File(_schemaFixturePath).readAsStringSync(),
      );
      final controller = EditController(
        graph: graph,
        metamodel: metamodel,
        database: db,
        fileId: fileId,
      );
      addTearDown(controller.dispose);

      controller.apply(
        const SetAttributeValueOp(
          elementId: '_line1',
          attributeName: 'name',
          newValue: 'Renamed Feeder 12',
          oldValue: 'Feeder 12',
        ),
      );

      final patched = controller.renderPatchedSource();
      File(modelPath).writeAsStringSync(patched);
      git
        ..stage('model.xml')
        ..commit('rename _line1');
      final secondSha = git.head()!.sha;

      final diff = git.diffTreeToTree(firstSha, secondSha);
      expect(
        diff,
        contains('Feeder 12'),
        reason: 'old line must appear as a removal',
      );
      expect(
        diff,
        contains('Renamed Feeder 12'),
        reason: 'new line must appear as an addition',
      );
      expect(
        countChangedLines(diff),
        lessThanOrEqualTo(2),
        reason: 'FR-4.2: a single-cell surgical edit must change ≤ 2 lines '
            '— observed: ${countChangedLines(diff)} changed lines',
      );
    });
  });

  group('M5 gate — branch + checkout round-trip', () {
    test('two diverging commits remain accessible by checking out each branch',
        () async {
      final repoDir = _newTempRepo();
      addTearDown(() {
        try {
          repoDir.deleteSync(recursive: true);
        } on FileSystemException {/* Windows */}
      });

      final fixtureSource = File(_sampleFixturePath).readAsStringSync();
      File(p.join(repoDir.path, 'model.xml'))
          .writeAsStringSync(fixtureSource);

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
      final initialBranch = git.currentBranch();
      expect(initialBranch, isNotNull);

      git
        ..createBranch(name: 'feature', fromSha: initialSha)
        ..checkoutBranch('feature');

      // Make a feature-branch commit.
      File(p.join(repoDir.path, 'model.xml'))
          .writeAsStringSync('$fixtureSource<!-- feature -->\n');
      git
        ..stage('model.xml')
        ..commit('feature change');
      final featureContent =
          File(p.join(repoDir.path, 'model.xml')).readAsStringSync();
      expect(featureContent, contains('<!-- feature -->'));

      // Back to the initial branch — working tree must match the seed.
      git.checkoutBranch(initialBranch!);
      final mainContent =
          File(p.join(repoDir.path, 'model.xml')).readAsStringSync();
      expect(mainContent, fixtureSource);
      expect(git.currentBranch(), initialBranch);

      // And the feature branch is still listed.
      expect(git.listBranches(), containsAll([initialBranch, 'feature']));
    });
  });
}
