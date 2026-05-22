import 'dart:io';

import 'package:cim_forge/features/diff/text_diff_view.dart';
import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/git/credential_store.dart';
import 'package:cim_forge/features/git/git_repo.dart';
import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart' as g;

/// Side panel surfacing Git operations against the project's repo:
///   - pending changes from [EditController] (FR-4.4)
///   - commit (write the patched source + stage + commit)
///   - branch listing + checkout / add remote
///   - pull / push with credentials from the OS keystore (FR-5.7)
///   - commit log
///   - tree-to-tree diff between two adjacent commits
class GitPanel extends StatefulWidget {
  const GitPanel({
    required this.repo,
    required this.editController,
    required this.modelFilePath,
    required this.onModelCommitted,
    this.credentialStore,
    super.key,
  });

  final GitRepo repo;
  final EditController editController;

  /// Repo-relative path of the model file the editor is currently working
  /// on. When the user clicks "commit", we write the rendered patched source
  /// here and stage this path.
  final String modelFilePath;

  /// Notifies the parent that a commit just succeeded — typically used to
  /// rebuild the open project view against the freshly-written source.
  final VoidCallback onModelCommitted;

  /// Stores per-remote auth bundles in the OS keystore. Pass an
  /// [InMemorySecureStorage]-backed store in tests to avoid platform IO.
  final CredentialStore? credentialStore;

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  late List<CommitInfo> _log;
  late List<String> _branches;
  late List<RemoteInfo> _remotes;
  String? _currentBranch;
  String? _selectedCommitSha;
  String? _selectedRemote;
  String _diffText = '';
  String? _error;
  String? _status;

  /// Sync cache of remote-URL → credential bundle, populated from the
  /// async [CredentialStore] on init and kept in step on save/delete.
  /// Needed because git2dart's credential callback is synchronous.
  final Map<String, CredentialBundle> _credCache = {};

  CredentialStore get _credStore {
    final injected = widget.credentialStore;
    if (injected != null) return injected;
    return _defaultStore ??= CredentialStore(
      storage: FlutterSecureStorageAdapter(),
    );
  }

  CredentialStore? _defaultStore;

  @override
  void initState() {
    super.initState();
    widget.editController.addListener(_refresh);
    _refresh();
    _preloadCredentials();
  }

  @override
  void dispose() {
    widget.editController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _log = widget.repo.log();
      _branches = widget.repo.listBranches();
      _remotes = widget.repo.listRemotes();
      _currentBranch = widget.repo.currentBranch();
      _selectedRemote ??=
          _remotes.isNotEmpty ? _remotes.first.name : null;
    });
  }

  Future<void> _preloadCredentials() async {
    for (final remote in widget.repo.listRemotes()) {
      final bundle = await _credStore.load(remote.url);
      if (bundle != null) _credCache[remote.url] = bundle;
    }
  }

  /// The sync credential resolver passed to fetch / pull / push. Looks up
  /// the cached bundle for the remote URL and returns the matching
  /// git2dart `Credentials`. Returns null for unknown remotes (libgit2
  /// then falls back to anonymous / agent depending on the URL).
  g.Credentials? _resolveCredentials(String url, String? username) {
    final bundle = _credCache[url];
    return bundle?.toGit2Dart();
  }

  Future<void> _pull() async {
    final remote = _selectedRemote;
    if (remote == null) {
      setState(() => _error = 'No remote configured');
      return;
    }
    try {
      final result = widget.repo.pull(
        remote,
        credentialResolver: _resolveCredentials,
      );
      setState(() {
        _error = null;
        _status = switch (result.kind) {
          PullKind.upToDate => 'Up to date with $remote',
          PullKind.fastForwarded =>
            'Fast-forwarded to ${result.fastForwardedTo?.substring(0, 7)}',
          PullKind.divergent =>
            'Diverged from $remote — manual merge required',
        };
      });
      widget.onModelCommitted();
      _refresh();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _push() async {
    final remote = _selectedRemote;
    if (remote == null) {
      setState(() => _error = 'No remote configured');
      return;
    }
    try {
      widget.repo.push(
        remote,
        credentialResolver: _resolveCredentials,
      );
      setState(() {
        _error = null;
        _status = 'Pushed to $remote';
      });
      _refresh();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _addRemote() async {
    final result = await showDialog<_AddRemoteResult>(
      context: context,
      builder: (_) => const _AddRemoteDialog(),
    );
    if (result == null) return;
    try {
      widget.repo.addRemote(name: result.name, url: result.url);
      if (result.bundle != null) {
        await _credStore.save(result.url, result.bundle!);
        _credCache[result.url] = result.bundle!;
      }
      _refresh();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _commit() async {
    final controller = widget.editController;
    if (!controller.hasPendingEdits) return;
    final message = await _promptCommitMessage();
    if (message == null) return;
    try {
      final patched = controller.renderPatchedSource();
      File(
        '${widget.repo.rootDirectory.path}${Platform.pathSeparator}'
        '${widget.modelFilePath}',
      ).writeAsStringSync(patched);
      widget.repo
        ..stage(widget.modelFilePath)
        ..commit(message);
      _error = null;
      widget.onModelCommitted();
      _refresh();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<String?> _promptCommitMessage() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Commit'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Commit message',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Commit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<void> _checkout(String branch) async {
    try {
      widget.repo.checkoutBranch(branch);
      _error = null;
      widget.onModelCommitted();
      _refresh();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _createBranch() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New branch'),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Branch name',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      widget.repo.createBranch(name: name);
      _refresh();
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _selectCommit(CommitInfo commit) {
    final parentIndex = _log.indexOf(commit) + 1;
    if (parentIndex >= _log.length) {
      // No parent — show the commit's introduction by diffing against an
      // empty tree is non-trivial here; surface a hint instead.
      setState(() {
        _selectedCommitSha = commit.sha;
        _diffText = '(initial commit — diff vs. empty tree not shown)';
      });
      return;
    }
    final parent = _log[parentIndex];
    try {
      final diff = widget.repo.diffTreeToTree(parent.sha, commit.sha);
      setState(() {
        _selectedCommitSha = commit.sha;
        _diffText = diff;
      });
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPending = widget.editController.hasPendingEdits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(text: 'Branch'),
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _currentBranch,
                items: [
                  for (final b in _branches)
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: (b) {
                  if (b != null) _checkout(b);
                },
              ),
            ),
            IconButton(
              tooltip: 'New branch',
              onPressed: _createBranch,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const Divider(),
        const _SectionHeader(text: 'Pending'),
        Text(
          hasPending
              ? '${widget.editController.pendingValues.length} cell edit(s)'
              : '(none)',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: hasPending ? _commit : null,
          icon: const Icon(Icons.check),
          label: const Text('Commit pending edits'),
        ),
        const Divider(),
        const _SectionHeader(text: 'Remote'),
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedRemote,
                hint: const Text('(none)'),
                items: [
                  for (final r in _remotes)
                    DropdownMenuItem(value: r.name, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _selectedRemote = v),
              ),
            ),
            IconButton(
              tooltip: 'Add remote',
              onPressed: _addRemote,
              icon: const Icon(Icons.add_link),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectedRemote == null ? null : _pull,
                icon: const Icon(Icons.download),
                label: const Text('Pull'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectedRemote == null ? null : _push,
                icon: const Icon(Icons.upload),
                label: const Text('Push'),
              ),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 4),
          Text(_status!, style: theme.textTheme.bodySmall),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const Divider(),
        const _SectionHeader(text: 'History'),
        SizedBox(
          height: 220,
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (context, i) {
              final c = _log[i];
              final selected = c.sha == _selectedCommitSha;
              return ListTile(
                dense: true,
                selected: selected,
                onTap: () => _selectCommit(c),
                title: Text(
                  c.message.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${c.shortSha} · ${c.authorName}'),
              );
            },
          ),
        ),
        const Divider(),
        const _SectionHeader(text: 'Diff'),
        Expanded(
          child: _diffText.isEmpty
              ? const Center(child: Text('Select a commit to view its diff'))
              : TextDiffView(diffText: _diffText),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Carries the result of the Add Remote dialog: the remote name + URL, plus
/// (optionally) the credential bundle the user chose to save.
class _AddRemoteResult {
  const _AddRemoteResult({
    required this.name,
    required this.url,
    required this.bundle,
  });
  final String name;
  final String url;
  final CredentialBundle? bundle;
}

enum _AuthKind { anonymous, httpsToken, sshKey, sshAgent }

class _AddRemoteDialog extends StatefulWidget {
  const _AddRemoteDialog();

  @override
  State<_AddRemoteDialog> createState() => _AddRemoteDialogState();
}

class _AddRemoteDialogState extends State<_AddRemoteDialog> {
  final _nameController = TextEditingController(text: 'origin');
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _tokenController = TextEditingController();
  final _pubKeyController = TextEditingController();
  final _privKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  _AuthKind _authKind = _AuthKind.anonymous;
  bool _userTouchedAuth = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_autoSelectAuthFromUrl);
  }

  @override
  void dispose() {
    _urlController.removeListener(_autoSelectAuthFromUrl);
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    _pubKeyController.dispose();
    _privKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  /// Pick a sensible auth default from the URL scheme, unless the user has
  /// already touched the radio.
  void _autoSelectAuthFromUrl() {
    if (_userTouchedAuth) return;
    final url = _urlController.text.trim();
    final kind = _inferAuthKind(url);
    if (kind == _authKind) return;
    setState(() {
      _authKind = kind;
      if (kind == _AuthKind.sshAgent || kind == _AuthKind.sshKey) {
        if (_usernameController.text.isEmpty) {
          _usernameController.text = 'git';
        }
      }
    });
  }

  static _AuthKind _inferAuthKind(String url) {
    if (url.startsWith('https://') || url.startsWith('http://')) {
      return _AuthKind.httpsToken;
    }
    if (url.startsWith('git@') || url.startsWith('ssh://')) {
      return _AuthKind.sshAgent;
    }
    return _AuthKind.anonymous;
  }

  CredentialBundle? _buildBundle() {
    switch (_authKind) {
      case _AuthKind.anonymous:
        return null;
      case _AuthKind.httpsToken:
        final username = _usernameController.text.trim();
        final token = _tokenController.text;
        if (token.isEmpty) return null;
        return CredentialBundle.httpsToken(
          username: username.isEmpty ? 'git' : username,
          token: token,
        );
      case _AuthKind.sshKey:
        final username = _usernameController.text.trim();
        final pub = _pubKeyController.text.trim();
        final priv = _privKeyController.text.trim();
        if (priv.isEmpty || pub.isEmpty) return null;
        final pass = _passphraseController.text;
        return CredentialBundle.sshKey(
          username: username.isEmpty ? 'git' : username,
          publicKeyPath: pub,
          privateKeyPath: priv,
          passphrase: pass.isEmpty ? null : pass,
        );
      case _AuthKind.sshAgent:
        final username = _usernameController.text.trim();
        return CredentialBundle.sshAgent(
          username: username.isEmpty ? 'git' : username,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add remote'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://… or git@…',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_AuthKind>(
                initialValue: _authKind,
                decoration: const InputDecoration(labelText: 'Auth'),
                items: const [
                  DropdownMenuItem(
                    value: _AuthKind.anonymous,
                    child: Text('Anonymous'),
                  ),
                  DropdownMenuItem(
                    value: _AuthKind.httpsToken,
                    child: Text('HTTPS token'),
                  ),
                  DropdownMenuItem(
                    value: _AuthKind.sshKey,
                    child: Text('SSH key files'),
                  ),
                  DropdownMenuItem(
                    value: _AuthKind.sshAgent,
                    child: Text('SSH agent'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _authKind = v;
                    _userTouchedAuth = true;
                  });
                },
              ),
              const SizedBox(height: 8),
              ..._authFields(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final url = _urlController.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            Navigator.of(context).pop(
              _AddRemoteResult(
                name: name,
                url: url,
                bundle: _buildBundle(),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  List<Widget> _authFields() {
    switch (_authKind) {
      case _AuthKind.anonymous:
        return const [];
      case _AuthKind.httpsToken:
        return [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Personal access token',
            ),
          ),
        ];
      case _AuthKind.sshKey:
        return [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pubKeyController,
            decoration: const InputDecoration(
              labelText: 'Public key path',
              hintText: r'C:\Users\…\.ssh\id_ed25519.pub',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _privKeyController,
            decoration: const InputDecoration(
              labelText: 'Private key path',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase (optional)',
            ),
          ),
        ];
      case _AuthKind.sshAgent:
        return [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
        ];
    }
  }
}
