import 'package:cim_forge/features/git/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as g;

void main() {
  late CredentialStore store;

  setUp(() {
    store = CredentialStore(storage: InMemorySecureStorage());
  });

  test('save then load round-trips an HTTPS bundle', () async {
    const bundle = CredentialBundle.httpsToken(
      username: 'octocat',
      token: 'ghp_secret',
    );
    await store.save('https://example.test/repo.git', bundle);
    final loaded = await store.load('https://example.test/repo.git');
    expect(loaded?.kind, CredentialKind.httpsToken);
    expect(loaded?.username, 'octocat');
    expect(loaded?.token, 'ghp_secret');
  });

  test('save then load round-trips an SSH key bundle', () async {
    const bundle = CredentialBundle.sshKey(
      username: 'git',
      publicKeyPath: '/home/u/.ssh/id_ed25519.pub',
      privateKeyPath: '/home/u/.ssh/id_ed25519',
      passphrase: 'opensesame',
    );
    await store.save('git@example.test:fork/repo.git', bundle);
    final loaded = await store.load('git@example.test:fork/repo.git');
    expect(loaded?.kind, CredentialKind.sshKey);
    expect(loaded?.privateKeyPath, '/home/u/.ssh/id_ed25519');
    expect(loaded?.passphrase, 'opensesame');
    expect(loaded?.token, isNull);
  });

  test('save then load round-trips an SSH agent bundle', () async {
    const bundle = CredentialBundle.sshAgent(username: 'git');
    await store.save('git@example.test:repo.git', bundle);
    final loaded = await store.load('git@example.test:repo.git');
    expect(loaded?.kind, CredentialKind.sshAgent);
    expect(loaded?.username, 'git');
  });

  test('load returns null for unknown remote', () async {
    expect(await store.load('https://nothing.test/'), isNull);
  });

  test('delete removes the bundle', () async {
    await store.save(
      'https://x/',
      const CredentialBundle.httpsToken(username: 'u', token: 't'),
    );
    await store.delete('https://x/');
    expect(await store.load('https://x/'), isNull);
  });

  test('listRemoteUrls reports saved entries', () async {
    await store.save(
      'https://a.test/',
      const CredentialBundle.httpsToken(username: 'u', token: 't'),
    );
    await store.save(
      'git@b.test:r.git',
      const CredentialBundle.sshAgent(username: 'git'),
    );
    final urls = await store.listRemoteUrls();
    expect(urls, unorderedEquals(['https://a.test/', 'git@b.test:r.git']));
  });

  test('toGit2Dart yields the right Credentials shape', () {
    expect(
      const CredentialBundle.httpsToken(username: 'u', token: 't')
          .toGit2Dart(),
      isA<g.UserPass>(),
    );
    expect(
      const CredentialBundle.sshKey(
        username: 'git',
        publicKeyPath: '/a.pub',
        privateKeyPath: '/a',
      ).toGit2Dart(),
      isA<g.Keypair>(),
    );
    expect(
      const CredentialBundle.sshAgent(username: 'git').toGit2Dart(),
      isA<g.KeypairFromAgent>(),
    );
  });
}
