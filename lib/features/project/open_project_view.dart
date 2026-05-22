import 'dart:io';

import 'package:cim_forge/features/editing/edit_controller.dart';
import 'package:cim_forge/features/git/git_panel.dart';
import 'package:cim_forge/features/grid/grid_selection.dart';
import 'package:cim_forge/features/grid/grid_view.dart';
import 'package:cim_forge/features/model/background_indexer.dart';
import 'package:cim_forge/features/model/object_graph.dart';
import 'package:cim_forge/features/project/project.dart';
import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/features/schema/schema_loader.dart';
import 'package:cim_forge/features/views/query_engine.dart';
import 'package:cim_forge/features/views/query_grid_source.dart';
import 'package:cim_forge/features/views/view_definition.dart';
import 'package:cim_forge/features/views/view_store.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class OpenProjectView extends StatefulWidget {
  const OpenProjectView({required this.project, super.key});

  final Project project;

  @override
  State<OpenProjectView> createState() => _OpenProjectViewState();
}

class _OpenProjectViewState extends State<OpenProjectView> {
  late final ViewStore _viewStore = ViewStore(
    viewsDirectory: Directory(widget.project.layout.viewsDir),
  );

  final TextEditingController _schemaPath = TextEditingController();
  final TextEditingController _modelPath = TextEditingController();
  final GridSelection _selection = GridSelection();

  Metamodel? _metamodel;
  QueryEngine? _engine;
  String? _modelLoadedFromPath;
  EditController? _editController;
  List<String> _viewNames = const [];
  String? _selectedView;
  QueryGridSource? _gridSource;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshViews();
  }

  @override
  void dispose() {
    _schemaPath.dispose();
    _modelPath.dispose();
    _selection.dispose();
    _gridSource?.dispose();
    _editController?.dispose();
    super.dispose();
  }

  void _refreshViews() {
    setState(() {
      _viewNames = _viewStore.listNames();
    });
  }

  Future<void> _loadSchema() async {
    final path = _schemaPath.text.trim();
    if (path.isEmpty) return;
    try {
      final source = await File(path).readAsString();
      final m = SchemaLoader.load(source);
      setState(() {
        _metamodel = m;
        _engine = QueryEngine(metamodel: m);
        _status = 'Schema loaded — ${m.classes.length} classes';
        _error = null;
      });
    } on Exception catch (e) {
      setState(() => _error = 'Schema load failed: $e');
    }
  }

  Future<void> _loadModel() async {
    final path = _modelPath.text.trim();
    if (path.isEmpty) return;
    final metamodel = _metamodel;
    if (metamodel == null) {
      setState(() => _error = 'Load a schema first');
      return;
    }
    try {
      setState(() => _status = 'Parsing $path…');
      final source = await File(path).readAsString();
      final graph = ObjectGraph.parse(source);

      // The grid source holds a reference to the project's DB handle; that
      // handle is about to be released for the background indexer. Drop the
      // grid (the view picker rebuilds it on demand after reload).
      final oldGrid = _gridSource;
      _gridSource = null;
      oldGrid?.dispose();

      // Hand the SQLite file to a worker isolate. We release before the
      // worker runs and reopen after, both for the happy path and on error.
      setState(() => _status = 'Indexing ${graph.elementCount} elements…');
      widget.project.releaseDatabase();
      late BackgroundIndexResult result;
      try {
        result = await BackgroundIndexer.run(
          sourcePath: path,
          dbPath: widget.project.layout.indexPath,
          onProgress: (processed, total) {
            if (!mounted) return;
            setState(() => _status = 'Indexing $processed / $total…');
          },
        );
      } finally {
        widget.project.reopenDatabase();
      }

      final oldController = _editController;
      final controller = EditController(
        graph: graph,
        metamodel: metamodel,
        database: widget.project.database,
        fileId: result.fileId,
      );
      setState(() {
        _modelLoadedFromPath = path;
        _editController = controller;
        _status = 'Indexed ${result.elementCount} elements in '
            '${result.totalDuration.inMilliseconds}ms';
        _error = null;
      });
      oldController?.dispose();
    } on Exception catch (e) {
      setState(() => _error = 'Model load failed: $e');
    }
  }

  Future<void> _reloadAfterCommit() async {
    // After a commit, the on-disk model is up to date; reload it so the
    // EditController's graph anchors against the new file (and surgical
    // patches resume from a clean state).
    if (_modelLoadedFromPath != null) {
      await _loadModel();
      final selected = _selectedView;
      if (selected != null) await _openView(selected);
    }
  }

  Future<void> _openView(String name) async {
    final engine = _engine;
    if (engine == null) return;
    final view = _viewStore.load(name);
    final source = QueryGridSource(
      database: widget.project.database,
      engine: engine,
      view: view,
      editController: _editController,
    );
    final old = _gridSource;
    setState(() {
      _selectedView = name;
      _gridSource = source;
      _error = null;
    });
    old?.dispose();
  }

  Future<void> _createView() async {
    final m = _metamodel;
    if (m == null) {
      setState(() => _error = 'Load a schema first');
      return;
    }
    final result = await showDialog<ViewDefinition>(
      context: context,
      builder: (_) => _NewViewDialog(metamodel: m),
    );
    if (result == null) return;
    try {
      _viewStore.save(result);
      _refreshViews();
      await _openView(result.name);
    } on Exception catch (e) {
      setState(() => _error = 'Could not save view: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LoaderBar(
            schemaController: _schemaPath,
            modelController: _modelPath,
            onLoadSchema: _loadSchema,
            onLoadModel: _loadModel,
            schemaLoaded: _metamodel != null,
            modelLoaded: _modelLoadedFromPath != null,
          ),
          const SizedBox(height: 8),
          if (_status != null)
            Text(_status!, style: theme.textTheme.bodySmall),
          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('View:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedView,
                hint: const Text('(none)'),
                items: [
                  for (final name in _viewNames)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: _modelLoadedFromPath == null
                    ? null
                    : (v) {
                        if (v != null) _openView(v);
                      },
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _metamodel == null ? null : _createView,
                icon: const Icon(Icons.add),
                label: const Text('New view'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: _gridSource == null
                        ? const Center(
                            child: Text(
                              'Load schema + model, then open a view',
                            ),
                          )
                        : CimGridView(
                            source: _gridSource!,
                            selection: _selection,
                          ),
                  ),
                ),
                if (_editController != null && _modelLoadedFromPath != null)
                  SizedBox(
                    width: 360,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: GitPanel(
                        repo: widget.project.gitRepo,
                        editController: _editController!,
                        modelFilePath: p.relative(
                          _modelLoadedFromPath!,
                          from: widget.project.layout.rootPath,
                        ),
                        onModelCommitted: _reloadAfterCommit,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoaderBar extends StatelessWidget {
  const _LoaderBar({
    required this.schemaController,
    required this.modelController,
    required this.onLoadSchema,
    required this.onLoadModel,
    required this.schemaLoaded,
    required this.modelLoaded,
  });

  final TextEditingController schemaController;
  final TextEditingController modelController;
  final VoidCallback onLoadSchema;
  final VoidCallback onLoadModel;
  final bool schemaLoaded;
  final bool modelLoaded;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 80, child: Text('Schema')),
            Expanded(
              child: TextField(
                controller: schemaController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'path/to/schema.rdfs',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onLoadSchema,
              child: Text(schemaLoaded ? 'Reload' : 'Load'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 80, child: Text('Model')),
            Expanded(
              child: TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'path/to/model.xml',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: schemaLoaded ? onLoadModel : null,
              child: Text(modelLoaded ? 'Reload' : 'Load'),
            ),
          ],
        ),
      ],
    );
  }
}

class _NewViewDialog extends StatefulWidget {
  const _NewViewDialog({required this.metamodel});
  final Metamodel metamodel;

  @override
  State<_NewViewDialog> createState() => _NewViewDialogState();
}

class _NewViewDialogState extends State<_NewViewDialog> {
  final _nameController = TextEditingController();
  String? _baseClass;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classes = widget.metamodel.classes.map((c) => c.name).toList()
      ..sort();
    return AlertDialog(
      title: const Text('New view'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'View name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _baseClass,
              hint: const Text('Base class'),
              items: [
                for (final c in classes)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _baseClass = v),
            ),
          ],
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
            final base = _baseClass;
            if (!ViewStore.isValidName(name) || base == null) return;
            final attrs = widget.metamodel.attributesOf(base);
            final columns = [
              for (final a in attrs.take(8)) ColumnDefinition(path: [a.name]),
            ];
            if (columns.isEmpty) {
              columns.add(const ColumnDefinition(path: ['name']));
            }
            Navigator.of(context).pop(
              ViewDefinition(
                name: name,
                baseClass: base,
                columns: columns,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
