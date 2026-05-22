// Dedicated Linux smoke test for the prebuilt libgit2 binary shipped by
// `git2dart_binaries`. This is the Linux half of the deployment story flagged
// by the TR-9.2 spike — the Windows half is already exercised by every
// GitRepo test on the Windows runner.
//
// Why a separate test instead of relying on the existing M5/M8 gates:
//   - When it fails, the failure unambiguously points at the libgit2/.so
//     load path, not at anything else. The bigger gate tests exercise
//     parsing, indexing, EditController etc. — a load failure there is
//     harder to triage.
//   - We skip on non-Linux platforms so green/red status in CI maps 1:1
//     to "does Linux work?" without noise.
//   - The exercises are minimal — init repo, commit, log, diff. Enough to
//     prove libgit2 + libssh2 + system OpenSSL line up; not so much that
//     a parser bug masks the load failure.
//
// What to do with the result:
//   - PASS  → Ubuntu's libssl3 is wire-compatible; system-OpenSSL packaging
//             (deb / AppImage / Flatpak with runtime OpenSSL) is viable.
//             See packaging/linux/README.md.
//   - FAIL with "Failed to load dynamic library" → OpenSSL mismatch. Most
//             likely libssh2 wants libssl.so.3 but the runtime has .1.1.
//             Either bundle libssl3 in the package or use Flatpak runtime.
//   - FAIL otherwise → git2dart bug; file upstream with the trace.

import 'dart:io';

import 'package:cim_forge/features/git/git_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('libgit2 loads and a minimal commit / diff round-trips on Linux',
      () {
    if (!Platform.isLinux) {
      // Not the platform we're checking — leave a clear breadcrumb in the
      // test report rather than silently passing.
      markTestSkipped('Linux-only — see test header for rationale.');
      return;
    }

    final dir = Directory.systemTemp.createTempSync('cim_forge_linux_libgit2_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Tolerate any FS race; not the point of this test.
      }
    });

    final repo = GitRepo.openOrInit(dir)
      ..ensureSignature(
        name: 'Linux Smoke',
        email: 'smoke@cim-forge.local',
      );
    addTearDown(repo.dispose);

    final modelPath = p.join(dir.path, 'model.xml');
    File(modelPath).writeAsStringSync('<a/>\n');
    repo
      ..stage('model.xml')
      ..commit('initial');
    final firstSha = repo.head()!.sha;

    File(modelPath).writeAsStringSync('<b/>\n');
    repo
      ..stage('model.xml')
      ..commit('change');
    final secondSha = repo.head()!.sha;

    final diff = repo.diffTreeToTree(firstSha, secondSha);
    expect(diff, contains('-<a/>'));
    expect(diff, contains('+<b/>'));
    expect(repo.log(), hasLength(2));
  });
}
