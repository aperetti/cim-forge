import 'dart:io';

import 'package:cim_forge/features/git/git_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Directory _newTempRepo() =>
    Directory.systemTemp.createTempSync('cim_forge_git_repo_');

void _writeFile(Directory dir, String relativePath, String content) {
  final file = File(p.join(dir.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  late Directory dir;
  late GitRepo repo;

  setUp(() {
    dir = _newTempRepo();
    repo = GitRepo.openOrInit(dir)
      ..ensureSignature(name: 'CIM Forge Test', email: 'test@cim-forge.local');
  });

  tearDown(() {
    repo.dispose();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can be slow releasing handles to .pack files.
    }
  });

  test('openOrInit initializes a fresh repo with no commits', () {
    expect(repo.isEmpty, isTrue);
    expect(repo.head(), isNull);
    expect(repo.log(), isEmpty);
  });

  test('first commit creates HEAD and shows up in the log', () {
    _writeFile(dir, 'model.xml', '<rdf:RDF/>\n');
    repo
      ..stage('model.xml')
      ..commit('initial commit');
    expect(repo.isEmpty, isFalse);
    final head = repo.head();
    expect(head, isNotNull);
    expect(head!.message.trim(), 'initial commit');
    expect(repo.log(), hasLength(1));
  });

  test('a second commit appears in the log newest-first', () {
    _writeFile(dir, 'model.xml', 'one\n');
    repo
      ..stage('model.xml')
      ..commit('first');
    _writeFile(dir, 'model.xml', 'two\n');
    repo
      ..stage('model.xml')
      ..commit('second');
    final log = repo.log();
    expect(log, hasLength(2));
    expect(log.first.message.trim(), 'second');
    expect(log.last.message.trim(), 'first');
  });

  test('tree-to-tree diff shows the line changed between two commits', () {
    _writeFile(dir, 'model.xml', '<rdf:RDF>\n  <a/>\n</rdf:RDF>\n');
    repo
      ..stage('model.xml')
      ..commit('initial');
    final firstSha = repo.head()!.sha;

    _writeFile(dir, 'model.xml', '<rdf:RDF>\n  <b/>\n</rdf:RDF>\n');
    repo
      ..stage('model.xml')
      ..commit('rename');
    final secondSha = repo.head()!.sha;

    final diff = repo.diffTreeToTree(firstSha, secondSha);
    expect(diff, contains('-  <a/>'));
    expect(diff, contains('+  <b/>'));
  });

  test('branch + checkout round-trips both states', () {
    _writeFile(dir, 'model.xml', 'main one\n');
    repo
      ..stage('model.xml')
      ..commit('main initial');
    final mainSha = repo.head()!.sha;

    repo.createBranch(name: 'feature', fromSha: mainSha);
    expect(repo.listBranches(), containsAll(['master', 'feature']));
    repo.checkoutBranch('feature');
    expect(repo.currentBranch(), 'feature');

    _writeFile(dir, 'model.xml', 'feature one\n');
    repo
      ..stage('model.xml')
      ..commit('feature change');

    // Working tree should reflect the feature commit.
    expect(File(p.join(dir.path, 'model.xml')).readAsStringSync(),
        'feature one\n');

    repo.checkoutBranch('master');
    expect(repo.currentBranch(), 'master');
    expect(File(p.join(dir.path, 'model.xml')).readAsStringSync(),
        'main one\n');
  });

  test('stageAll picks up new and modified files', () {
    _writeFile(dir, 'a.xml', 'one\n');
    repo
      ..stageAll()
      ..commit('initial');

    _writeFile(dir, 'a.xml', 'two\n');
    _writeFile(dir, 'b.xml', 'new\n');
    repo
      ..stageAll()
      ..commit('change + add');

    final log = repo.log();
    expect(log, hasLength(2));
  });
}
