import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:git2dart/git2dart.dart' as g;
import 'package:meta/meta.dart';

/// Minimal key/value interface the [CredentialStore] needs from a backing
/// secret store. Production wires this to the OS keystore (Windows
/// Credential Manager via `flutter_secure_storage`, libsecret on Linux);
/// tests provide [InMemorySecureStorage].
abstract class KeyValueSecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<List<String>> listKeys();
}

class InMemorySecureStorage implements KeyValueSecureStorage {
  final Map<String, String> _entries = {};

  @override
  Future<String?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, String value) async {
    _entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<List<String>> listKeys() async => _entries.keys.toList();
}

/// Adapts `flutter_secure_storage` to [KeyValueSecureStorage]. Backs
/// Windows Credential Manager, libsecret on Linux, and Keychain on macOS
/// via a single API.
class FlutterSecureStorageAdapter implements KeyValueSecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<List<String>> listKeys() async {
    final all = await _storage.readAll();
    return all.keys.toList();
  }
}

/// What kind of authentication this bundle represents.
enum CredentialKind {
  /// Username + token (HTTPS). Maps to git2dart `UserPass`.
  httpsToken,

  /// SSH key files on disk. Maps to git2dart `Keypair`.
  sshKey,

  /// Defer to a running SSH agent. Maps to git2dart `KeypairFromAgent`.
  sshAgent,
}

/// Stored authentication for one remote. Mutual-exclusive fields are
/// populated according to [kind]; FR-5.7 forbids storing plaintext in the
/// repo, hence this lives behind a [KeyValueSecureStorage].
@immutable
class CredentialBundle {
  const CredentialBundle.httpsToken({
    required this.username,
    required String token,
  }) : kind = CredentialKind.httpsToken,
       _secret = token,
       publicKeyPath = null,
       privateKeyPath = null,
       passphrase = null;

  const CredentialBundle.sshKey({
    required this.username,
    required this.publicKeyPath,
    required this.privateKeyPath,
    this.passphrase,
  }) : kind = CredentialKind.sshKey,
       _secret = null;

  const CredentialBundle.sshAgent({required this.username})
    : kind = CredentialKind.sshAgent,
      _secret = null,
      publicKeyPath = null,
      privateKeyPath = null,
      passphrase = null;

  const CredentialBundle._({
    required this.kind,
    required this.username,
    String? secret,
    this.publicKeyPath,
    this.privateKeyPath,
    this.passphrase,
  }) : _secret = secret;

  factory CredentialBundle._fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String?;
    final kind = CredentialKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () =>
          throw FormatException('Unknown CredentialKind: $kindName'),
    );
    return CredentialBundle._(
      kind: kind,
      username: (json['username'] as String?) ?? '',
      secret: json['secret'] as String?,
      publicKeyPath: json['publicKeyPath'] as String?,
      privateKeyPath: json['privateKeyPath'] as String?,
      passphrase: json['passphrase'] as String?,
    );
  }

  final CredentialKind kind;
  final String username;

  /// HTTPS token. Null for SSH bundles. Hidden via getter to discourage
  /// accidental logging.
  final String? _secret;
  String? get token => kind == CredentialKind.httpsToken ? _secret : null;

  final String? publicKeyPath;
  final String? privateKeyPath;
  final String? passphrase;

  /// Builds the git2dart credentials object expected by the auth callback.
  g.Credentials toGit2Dart() {
    switch (kind) {
      case CredentialKind.httpsToken:
        return g.UserPass(
          username: username,
          password: _secret ?? '',
        );
      case CredentialKind.sshKey:
        return g.Keypair(
          username: username,
          pubKey: publicKeyPath ?? '',
          privateKey: privateKeyPath ?? '',
          passPhrase: passphrase ?? '',
        );
      case CredentialKind.sshAgent:
        return g.KeypairFromAgent(username);
    }
  }

  Map<String, Object?> _toJson() => {
    'kind': kind.name,
    'username': username,
    if (_secret != null) 'secret': _secret,
    if (publicKeyPath != null) 'publicKeyPath': publicKeyPath,
    if (privateKeyPath != null) 'privateKeyPath': privateKeyPath,
    if (passphrase != null) 'passphrase': passphrase,
  };
}

const String _keyPrefix = 'cim-forge/remote/';

/// Maps remote URLs to [CredentialBundle]s, persisted in a
/// [KeyValueSecureStorage]. Wrap with a `CredentialResolver`-shaped
/// callback to pass to fetch/pull/push.
class CredentialStore {
  CredentialStore({required this.storage});

  final KeyValueSecureStorage storage;

  Future<void> save(String remoteUrl, CredentialBundle bundle) async {
    await storage.write(
      _keyPrefix + remoteUrl,
      jsonEncode(bundle._toJson()),
    );
  }

  Future<CredentialBundle?> load(String remoteUrl) async {
    final raw = await storage.read(_keyPrefix + remoteUrl);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return null;
    return CredentialBundle._fromJson(decoded);
  }

  Future<void> delete(String remoteUrl) async {
    await storage.delete(_keyPrefix + remoteUrl);
  }

  Future<List<String>> listRemoteUrls() async {
    final keys = await storage.listKeys();
    return [
      for (final key in keys)
        if (key.startsWith(_keyPrefix)) key.substring(_keyPrefix.length),
    ];
  }
}
