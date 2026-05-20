import 'dart:io';

import 'package:cim_forge/features/project/open_project_view.dart';
import 'package:cim_forge/features/project/project.dart';
import 'package:cim_forge/features/settings/settings.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CimForgeApp());
}

class CimForgeApp extends StatelessWidget {
  const CimForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIM Forge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final SettingsStore _settingsStore = SettingsStore();
  UserSettings _settings = UserSettings();
  Project? _project;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _createProject(String path) async {
    await _withLifecycle(() => Project.create(Directory(path)), path);
  }

  Future<void> _openProject(String path) async {
    await _withLifecycle(() => Project.open(Directory(path)), path);
  }

  Future<void> _withLifecycle(
    Project Function() open,
    String path,
  ) async {
    try {
      final project = open();
      _settings.touchRecentProject(path);
      await _settingsStore.save(_settings);
      if (!mounted) return;
      setState(() {
        _project = project;
        _lastError = null;
      });
    } on Exception catch (e) {
      setState(() => _lastError = e.toString());
    }
  }

  void _closeProject() {
    _project?.close();
    setState(() => _project = null);
  }

  @override
  void dispose() {
    _project?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          project == null
              ? 'CIM Forge'
              : 'CIM Forge — ${project.layout.rootPath}',
        ),
        actions: [
          if (project != null)
            IconButton(
              tooltip: 'Close project',
              onPressed: _closeProject,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: project == null
          ? _ProjectPickerView(
              settings: _settings,
              error: _lastError,
              onCreate: _createProject,
              onOpen: _openProject,
            )
          : OpenProjectView(project: project),
    );
  }
}

class _ProjectPickerView extends StatefulWidget {
  const _ProjectPickerView({
    required this.settings,
    required this.error,
    required this.onCreate,
    required this.onOpen,
  });

  final UserSettings settings;
  final String? error;
  final ValueChanged<String> onCreate;
  final ValueChanged<String> onOpen;

  @override
  State<_ProjectPickerView> createState() => _ProjectPickerViewState();
}

class _ProjectPickerViewState extends State<_ProjectPickerView> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Open a CIM Forge project',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              labelText: 'Project directory',
              hintText: r'C:\path\to\repo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: () => widget.onOpen(_pathController.text.trim()),
                child: const Text('Open'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => widget.onCreate(_pathController.text.trim()),
                child: const Text('Create'),
              ),
            ],
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          if (widget.settings.recentProjects.isNotEmpty) ...[
            Text('Recent', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.settings.recentProjects.length,
                itemBuilder: (context, i) {
                  final path = widget.settings.recentProjects[i];
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(path),
                    onTap: () => widget.onOpen(path),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
