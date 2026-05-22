import 'dart:io';

import 'package:git2dart/git2dart.dart' as g;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Resolves authentication credentials for a remote operation. The resolver
/// gets the remote URL and the username the server requested (often null for
/// HTTPS; usually `git` for SSH); returns null to fall through to anonymous.
typedef CredentialResolver = g.Credentials? Function(
  String url,
  String? usernameFromUrl,
);

@immutable
class RemoteInfo {
  const RemoteInfo({
    required this.name,
    required this.url,
    required this.pushUrl,
  });
  final String name;
  final String url;
  final String pushUrl;
}

@immutable
class PullResult {
  const PullResult({required this.kind, this.fastForwardedTo});
  final PullKind kind;
  final String? fastForwardedTo;
}

enum PullKind {
  /// Local HEAD already at or ahead of the remote — nothing to do.
  upToDate,

  /// Local HEAD was strictly behind; we fast-forwarded it.
  fastForwarded,

  /// Histories diverged — no commit was made. Caller should drive a merge.
  divergent,
}

@immutable
class MergeConflictEntry {
  const MergeConflictEntry({
    required this.path,
    required this.ancestorSha,
    required this.ourSha,
    required this.theirSha,
  });

  /// Repo-relative path of the conflicting file.
  final String path;

  /// Blob SHA at the merge base (may be null if the file is new on both
  /// sides — a "both-added" conflict).
  final String? ancestorSha;
  final String? ourSha;
  final String? theirSha;
}

@immutable
class CommitInfo {
  const CommitInfo({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.authorEmail,
    required this.time,
  });

  final String sha;
  final String message;
  final String authorName;
  final String authorEmail;
  final DateTime time;

  String get shortSha => sha.length >= 7 ? sha.substring(0, 7) : sha;
}

class GitRepoException implements Exception {
  GitRepoException(this.message);
  final String message;
  @override
  String toString() => 'GitRepoException: $message';
}

/// Thin wrapper over `git2dart` (TR-7.1). Confines all `git2dart` types to
/// this file so the rest of the app talks to a small, app-shaped Git API.
///
/// Lifecycle: the wrapper owns the underlying `Repository` pointer and frees
/// it on [dispose]. Multiple operations re-use the same handle.
class GitRepo {
  GitRepo._(this._repo, this.rootDirectory);

  /// Clones [url] into [directory]. The directory must not exist or be
  /// empty. [credentialResolver] supplies auth on demand. FR-5.4.
  factory GitRepo.clone({
    required String url,
    required Directory directory,
    CredentialResolver? credentialResolver,
  }) {
    final raw = g.Repository.clone(
      url: url,
      localPath: directory.path,
      callbacks: _callbacksFor(credentialResolver),
    );
    raw.config['core.autocrlf'] = 'false';
    return GitRepo._(raw, directory);
  }

  /// Opens the Git repository at [directory], or initializes a fresh one if
  /// `.git` is not present. The returned wrapper owns the handle until
  /// [dispose] is called.
  factory GitRepo.openOrInit(Directory directory) {
    final gitDir = Directory(p.join(directory.path, '.git'));
    final g.Repository raw;
    if (gitDir.existsSync()) {
      raw = g.Repository.open(directory.path);
    } else {
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      raw = g.Repository.init(path: directory.path);
    }
    // CIM Forge's surgical patches rely on byte-stable line endings. CRLF
    // normalization (Git for Windows default) would shift offsets after a
    // round-trip through the index. Pin every CIM Forge repo to "no
    // conversion" so what we wrote is what gets checked out.
    raw.config['core.autocrlf'] = 'false';
    return GitRepo._(raw, directory);
  }

  final g.Repository _repo;
  final Directory rootDirectory;

  /// True when no commits exist yet (HEAD is unborn).
  bool get isEmpty => _repo.isEmpty;

  String get workdir => _repo.workdir;

  // ─── Status / staging ──────────────────────────────────────────────────

  /// Working-tree file paths that are modified or untracked relative to the
  /// index. Keys are repo-relative paths; values are the libgit2 status
  /// flags.
  Map<String, Set<g.GitStatus>> status() => Map.unmodifiable(_repo.status);

  /// Stage a single file by repo-relative path. Equivalent to `git add`.
  void stage(String relativePath) {
    final index = _repo.index;
    if (_isTracked(relativePath)) {
      index.updateAll([relativePath]);
    } else {
      index.add(relativePath);
    }
    index.write();
  }

  /// Stage every modified or untracked path. Equivalent to `git add -A`.
  void stageAll() {
    final index = _repo.index;
    final paths = status().keys.toList();
    if (paths.isEmpty) return;
    // updateAll is a no-op for paths the index doesn't know yet, so split.
    final untracked = <String>[];
    final tracked = <String>[];
    for (final path in paths) {
      if (_isTracked(path)) {
        tracked.add(path);
      } else {
        untracked.add(path);
      }
    }
    for (final path in untracked) {
      index.add(path);
    }
    if (tracked.isNotEmpty) {
      index.updateAll(tracked);
    }
    index.write();
  }

  bool _isTracked(String relativePath) {
    try {
      // Throws if the entry isn't in the index.
      final entry = _repo.index[relativePath];
      return entry.path.isNotEmpty;
    } on Object {
      return false;
    }
  }

  // ─── Commits ───────────────────────────────────────────────────────────

  /// Sets the repo's user.name / user.email if either is currently missing.
  /// Useful before the very first commit on machines that haven't run
  /// `git config --global user.name`.
  void ensureSignature({String? name, String? email}) {
    final config = _repo.config;
    if (name != null && _missingConfig(config, 'user.name')) {
      config['user.name'] = name;
    }
    if (email != null && _missingConfig(config, 'user.email')) {
      config['user.email'] = email;
    }
  }

  bool _missingConfig(g.Config config, String key) {
    try {
      final value = config[key].value;
      return value.isEmpty;
    } on Object {
      return true;
    }
  }

  /// Commit the current index. Falls back to libgit2's `Commit.create`
  /// with empty parents when no HEAD exists yet (first commit).
  String commit(String message) {
    final signature = _repo.defaultSignature;
    _repo.index.write();
    if (isEmpty) {
      final treeOid = _repo.index.writeTree();
      final oid = g.Commit.create(
        repo: _repo,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: message,
        tree: g.Tree.lookup(repo: _repo, oid: treeOid),
        parents: const [],
      );
      return oid.sha;
    }
    final parentOid = _repo.head.target;
    final parent = g.Commit.lookup(repo: _repo, oid: parentOid);
    final treeOid = _repo.index.writeTree();
    final oid = g.Commit.create(
      repo: _repo,
      updateRef: 'HEAD',
      author: signature,
      committer: signature,
      message: message,
      tree: g.Tree.lookup(repo: _repo, oid: treeOid),
      parents: [parent],
    );
    return oid.sha;
  }

  /// The current HEAD commit, or null if HEAD is unborn.
  CommitInfo? head() {
    if (isEmpty) return null;
    final commit = g.Commit.lookup(repo: _repo, oid: _repo.head.target);
    return _toCommitInfo(commit);
  }

  /// All commits reachable from HEAD, newest first, bounded by [limit].
  List<CommitInfo> log({int limit = 100}) {
    if (isEmpty) return const [];
    final commits = _repo.log(oid: _repo.head.target).take(limit);
    return [for (final c in commits) _toCommitInfo(c)];
  }

  CommitInfo _toCommitInfo(g.Commit commit) => CommitInfo(
    sha: commit.oid.sha,
    message: commit.message,
    authorName: commit.author.name,
    authorEmail: commit.author.email,
    time: DateTime.fromMillisecondsSinceEpoch(commit.time * 1000),
  );

  // ─── Branches ──────────────────────────────────────────────────────────

  /// Names of all local branches.
  List<String> listBranches() =>
      [for (final b in _repo.branches) b.name];

  /// Short name of the branch HEAD points at, or null if detached / unborn.
  String? currentBranch() {
    if (isEmpty) return null;
    try {
      return _repo.head.shorthand;
    } on Object {
      return null;
    }
  }

  /// Create a branch named [name] at the commit identified by [fromSha], or
  /// at HEAD if [fromSha] is null. Does not check it out.
  void createBranch({required String name, String? fromSha}) {
    final targetOid = fromSha == null
        ? _repo.head.target
        : _resolveSha(fromSha);
    final target = g.Commit.lookup(repo: _repo, oid: targetOid);
    g.Branch.create(repo: _repo, name: name, target: target);
  }

  /// Check out the branch named [name], moving HEAD and updating the
  /// working tree to match.
  void checkoutBranch(String name) {
    final fullName = 'refs/heads/$name';
    g.Checkout.reference(repo: _repo, name: fullName);
    _repo.setHead(fullName);
  }

  // ─── Remotes ───────────────────────────────────────────────────────────

  /// Adds a remote pointing at [url] under [name]. Throws if [name] already
  /// exists.
  void addRemote({required String name, required String url}) {
    g.Remote.create(repo: _repo, name: name, url: url);
  }

  /// Removes the remote configuration for [name]. Tracking refs survive.
  void removeRemote(String name) {
    g.Remote.delete(repo: _repo, name: name);
  }

  /// Lists all configured remotes.
  List<RemoteInfo> listRemotes() {
    return [
      for (final name in _repo.remotes)
        () {
          final remote = g.Remote.lookup(repo: _repo, name: name);
          return RemoteInfo(
            name: remote.name,
            url: remote.url,
            pushUrl: remote.pushUrl.isEmpty ? remote.url : remote.pushUrl,
          );
        }(),
    ];
  }

  /// Fetches from the named remote. Updates remote-tracking refs only — does
  /// NOT touch HEAD or the working tree. See [pull] for the combined op.
  void fetch(String remoteName, {CredentialResolver? credentialResolver}) {
    g.Remote.lookup(repo: _repo, name: remoteName)
        .fetch(callbacks: _callbacksFor(credentialResolver));
  }

  /// Fetch from [remoteName] then fast-forward HEAD to the matching
  /// remote-tracking branch if histories are linear. If they've diverged,
  /// returns [PullKind.divergent] without making a commit — the caller
  /// can drive a merge via [mergeBranch] / [conflicts]. FR-5.5.
  PullResult pull(
    String remoteName, {
    CredentialResolver? credentialResolver,
  }) {
    final branch = currentBranch();
    if (branch == null) {
      throw GitRepoException('Cannot pull while HEAD is detached or unborn');
    }
    fetch(remoteName, credentialResolver: credentialResolver);

    final trackingRefName = 'refs/remotes/$remoteName/$branch';
    final trackingRef = g.Reference.lookup(repo: _repo, name: trackingRefName);
    final theirHead = trackingRef.target;
    final analysis = g.Merge.analysis(repo: _repo, theirHead: theirHead);

    if (analysis.result.contains(g.GitMergeAnalysis.upToDate)) {
      return const PullResult(kind: PullKind.upToDate);
    }
    if (analysis.result.contains(g.GitMergeAnalysis.fastForward)) {
      // Move local branch ref to theirHead and force-update the working
      // tree to match. Force is safe for fast-forward because by
      // definition the local has no extra commits relative to the remote;
      // the default `safe` strategy would refuse since the workdir is
      // "behind" the ref it now points at.
      g.Reference.setTarget(
        repo: _repo,
        name: 'refs/heads/$branch',
        target: theirHead,
        logMessage: 'pull: fast-forward',
      );
      g.Checkout.head(
        repo: _repo,
        strategy: const {g.GitCheckout.force},
      );
      return PullResult(
        kind: PullKind.fastForwarded,
        fastForwardedTo: theirHead.sha,
      );
    }
    return const PullResult(kind: PullKind.divergent);
  }

  /// Push the current branch (or [localRefspec] if supplied) to [remoteName].
  /// Throws on auth failure or non-fast-forward (use force at your own risk
  /// — not exposed here, since CIM Forge's diff-friendliness depends on
  /// preserving history).
  void push(
    String remoteName, {
    String? localRefspec,
    CredentialResolver? credentialResolver,
  }) {
    final remote = g.Remote.lookup(repo: _repo, name: remoteName);
    final branch = currentBranch();
    if (branch == null && localRefspec == null) {
      throw GitRepoException(
        'Cannot push while HEAD is detached or unborn',
      );
    }
    final refspec = localRefspec ?? 'refs/heads/$branch:refs/heads/$branch';
    remote.push(
      refspecs: [refspec],
      callbacks: _callbacksFor(credentialResolver),
    );
  }

  static g.Callbacks _callbacksFor(CredentialResolver? resolver) {
    if (resolver == null) return const g.Callbacks();
    return g.Callbacks(credentials: _LazyCredentials(resolver));
  }

  // ─── Merge ─────────────────────────────────────────────────────────────

  /// Merges [theirBranch] into the current HEAD. After the call, check
  /// [conflicts] — non-empty means the merge produced text conflicts that
  /// the user must resolve before [commit]ing.
  void mergeBranch(String theirBranch) {
    final theirRef = g.Reference.lookup(
      repo: _repo,
      name: 'refs/heads/$theirBranch',
    );
    final commit = g.AnnotatedCommit.lookup(
      repo: _repo,
      oid: theirRef.target,
    );
    g.Merge.commit(repo: _repo, commit: commit);
  }

  /// Lists files with merge conflicts in the index along with the blob SHAs
  /// for ancestor / our / their sides. FR-6.4 — the UI projects these
  /// through `SemanticDiff` to surface conflicts at element level.
  List<MergeConflictEntry> conflicts() {
    final index = _repo.index;
    if (!index.hasConflicts) return const [];
    return [
      for (final entry in index.conflicts.entries)
        MergeConflictEntry(
          path: entry.key,
          ancestorSha: entry.value.ancestor?.oid.sha,
          ourSha: entry.value.our?.oid.sha,
          theirSha: entry.value.their?.oid.sha,
        ),
    ];
  }

  /// Reads the content of a blob by SHA. Used to fetch ancestor/our/their
  /// versions of a conflicting file for element-level diffing.
  String readBlob(String sha) {
    final oid = _resolveSha(sha);
    return g.Blob.lookup(repo: _repo, oid: oid).content;
  }

  /// Cleans up the in-flight merge state (`MERGE_HEAD`, etc.) without
  /// committing — typically after [conflicts] are resolved by other means or
  /// the user aborts.
  void abortMerge() {
    _repo.stateCleanup();
  }

  // ─── Diff ──────────────────────────────────────────────────────────────

  /// Unified-diff text between two commits (by short or full SHA).
  String diffTreeToTree(String oldSha, String newSha) {
    final oldOid = _resolveSha(oldSha);
    final newOid = _resolveSha(newSha);
    final oldTree = g.Commit.lookup(repo: _repo, oid: oldOid).tree;
    final newTree = g.Commit.lookup(repo: _repo, oid: newOid).tree;
    final diff = g.Diff.treeToTree(
      repo: _repo,
      oldTree: oldTree,
      newTree: newTree,
    );
    return diff.patch;
  }

  /// Unified-diff text between the index and the working tree (≈ `git diff`).
  String diffWorkdir() {
    final diff = g.Diff.indexToWorkdir(repo: _repo, index: _repo.index);
    return diff.patch;
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────

  void dispose() => _repo.free();

  // ─── internals ─────────────────────────────────────────────────────────

  g.Oid _resolveSha(String sha) {
    if (sha.length == 40) {
      return g.Oid.fromSHA(_repo, sha);
    }
    // Short SHA — round-trip via revparse single.
    final obj = g.RevParse.single(repo: _repo, spec: sha);
    if (obj is g.Commit) return obj.oid;
    if (obj is g.Tag) return obj.oid;
    throw GitRepoException('Cannot resolve "$sha" to a commit');
  }
}

/// Adapts a [CredentialResolver] into git2dart's [g.Credentials] interface.
/// libgit2 may call back multiple times for one operation (e.g. when the
/// server prompts with a specific username); we re-invoke the resolver each
/// time.
class _LazyCredentials implements g.Credentials {
  _LazyCredentials(this._resolver);
  final CredentialResolver _resolver;

  /// Resolve credentials for a specific URL/username combination — exposed
  /// for cases where the caller drives auth explicitly (e.g. a UI prompt).
  g.Credentials? resolve(String url, String? usernameFromUrl) =>
      _resolver(url, usernameFromUrl);

  @override
  g.GitCredential get credentialType {
    final resolved = _resolver('', null);
    if (resolved == null) {
      throw GitRepoException('No credentials supplied for remote operation');
    }
    return resolved.credentialType;
  }
}
