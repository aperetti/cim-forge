import 'dart:io';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/git/credential_store.dart';
import 'package:cim_forge/features/git/git_panel.dart';
import 'package:cim_forge/features/git/git_repo.dart';
import 'package:cim_forge/features/model/index_schema.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/shared/storage/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as g;

void main() {
  group('M8.3 — Add Remote dialog → CredentialStore round-trip', () {
    late Directory tempDir;
    late GitRepo repo;
    late CredentialStore store;
    late EditController controller;
    late AppDatabase db;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cim_forge_m83_');
      repo = GitRepo.openOrInit(tempDir)
        ..ensureSignature(
          name: 'M8.3 Test',
          email: 't@cim-forge.local',
        );
      store = CredentialStore(storage: InMemorySecureStorage());

      // Minimal EditController for the GitPanel constructor.
      db = AppDatabase.openInMemory(migrations: cimIndexMigrations);
      final graph = ObjectGraph.parse(
        File('test/fixtures/cim/sample.xml').readAsStringSync(),
      );
      final metamodel = SchemaLoader.load(
        File('test/fixtures/cim/sample_schema.rdfs').readAsStringSync(),
      );
      controller = EditController(
        graph: graph,
        metamodel: metamodel,
        database: db,
        fileId: 1,
      );
    });

    tearDown(() {
      controller.dispose();
      db.close();
      repo.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    Future<void> pumpPanel(WidgetTester tester) async {
      // GitPanel needs more vertical space than the default 800x600
      // viewport. Bump to 1200 so the History + Diff sections fit and
      // don't trip the overflow detector during these widget tests.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitPanel(
              repo: repo,
              editController: controller,
              modelFilePath: 'model.xml',
              onModelCommitted: () {},
              credentialStore: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('dialog defaults to HTTPS form when URL is https://',
        (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byTooltip('Add remote'));
      await tester.pumpAndSettle();

      // Enter URL — the auth dropdown should auto-switch to HTTPS token.
      await tester.enterText(find.bySemanticsLabel('URL'),
          'https://example.test/repo.git');
      await tester.pump();
      expect(find.text('Personal access token'), findsOneWidget);
    });

    testWidgets('dialog auto-selects SSH agent when URL is git@…',
        (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byTooltip('Add remote'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.bySemanticsLabel('URL'),
        'git@example.test:owner/repo.git',
      );
      await tester.pump();
      // SSH-agent form has the Username field but no token / key paths.
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Personal access token'), findsNothing);
      expect(find.text('Private key path'), findsNothing);
    });

    testWidgets(
      'submitting HTTPS form saves the bundle in CredentialStore '
      'and the resolver returns the matching credentials',
      (tester) async {
        await pumpPanel(tester);
        await tester.tap(find.byTooltip('Add remote'));
        await tester.pumpAndSettle();

        await tester.enterText(find.bySemanticsLabel('Name'), 'origin');
        await tester.enterText(
          find.bySemanticsLabel('URL'),
          'https://example.test/repo.git',
        );
        await tester.pump();
        await tester.enterText(
          find.bySemanticsLabel('Username'),
          'octocat',
        );
        await tester.enterText(
          find.bySemanticsLabel('Personal access token'),
          'ghp_TEST',
        );
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        final saved = await store.load('https://example.test/repo.git');
        expect(saved, isNotNull);
        expect(saved!.kind, CredentialKind.httpsToken);
        expect(saved.username, 'octocat');
        expect(saved.token, 'ghp_TEST');

        // The remote shows up in the repo's remote list — gate that the
        // panel actually added it (not just stored creds).
        expect(
          repo.listRemotes().map((r) => r.name),
          contains('origin'),
        );
      },
    );

    testWidgets(
      'submitting the anonymous form stores no credentials but adds remote',
      (tester) async {
        await pumpPanel(tester);
        await tester.tap(find.byTooltip('Add remote'));
        await tester.pumpAndSettle();
        // Default URL prefix is empty → auth defaults to Anonymous.
        await tester.enterText(find.bySemanticsLabel('Name'), 'mirror');
        await tester.enterText(
          find.bySemanticsLabel('URL'),
          r'C:\path\to\repo',
        );
        await tester.pump();
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(await store.load(r'C:\path\to\repo'), isNull);
        expect(repo.listRemotes().map((r) => r.name), contains('mirror'));
      },
    );
  });

  group('M8.3 — CredentialStore.toGit2Dart shape verification', () {
    test('httpsToken bundle round-trips through fetch credential callback',
        () async {
      final store = CredentialStore(storage: InMemorySecureStorage());
      const url = 'https://example.test/repo.git';
      await store.save(
        url,
        const CredentialBundle.httpsToken(username: 'u', token: 't'),
      );

      final loaded = await store.load(url);
      expect(loaded, isNotNull);
      final creds = loaded!.toGit2Dart();
      expect(creds, isA<g.UserPass>());
      expect((creds as g.UserPass).username, 'u');
      expect(creds.password, 't');
    });
  });
}

// The `bySemanticsLabel` extension on CommonFinders ships with flutter_test
// (matches a widget's semantic label). We rely on it as-is; nothing extra
// is defined here.
