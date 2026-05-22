import 'dart:convert';
import 'dart:io';

import 'package:cim_forge/features/views/view_definition.dart';
import 'package:path/path.dart' as p;

class ViewStoreException implements Exception {
  ViewStoreException(this.message);
  final String message;
  @override
  String toString() => 'ViewStoreException: $message';
}

/// Loads, saves, and lists [ViewDefinition]s under a project's `.cimviews/`
/// directory (TR-5.1). Each view is one `<name>.json` file. Filenames must
/// be filesystem-safe — see [isValidName].
class ViewStore {
  ViewStore({required this.viewsDirectory});

  /// Directory holding `<name>.json` files. Typically
  /// `<project-root>/.cimviews`.
  final Directory viewsDirectory;

  static final _safeName = RegExp(r'^[A-Za-z0-9 _.-]+$');

  static bool isValidName(String name) =>
      name.isNotEmpty && name.length <= 128 && _safeName.hasMatch(name);

  List<String> listNames() {
    if (!viewsDirectory.existsSync()) return const [];
    final out = <String>[];
    for (final entity in viewsDirectory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (p.extension(entity.path) == '.json' && isValidName(name)) {
        out.add(name);
      }
    }
    out.sort();
    return out;
  }

  ViewDefinition load(String name) {
    _requireName(name);
    final file = File(_pathFor(name));
    if (!file.existsSync()) {
      throw ViewStoreException('No view named "$name"');
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map<String, Object?>) {
      throw ViewStoreException('View "$name" is not a JSON object');
    }
    try {
      return ViewDefinition.fromJson(raw);
    } on FormatException catch (e) {
      throw ViewStoreException('View "$name" is malformed: ${e.message}');
    }
  }

  /// Writes [view] under its own name. Atomic: writes to a temp file then
  /// renames so concurrent reads never see a half-written file.
  void save(ViewDefinition view) {
    _requireName(view.name);
    if (!viewsDirectory.existsSync()) {
      viewsDirectory.createSync(recursive: true);
    }
    final target = _pathFor(view.name);
    final tmp = '$target.tmp';
    File(tmp).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(view.toJson()),
    );
    File(tmp).renameSync(target);
  }

  void delete(String name) {
    _requireName(name);
    final file = File(_pathFor(name));
    if (file.existsSync()) file.deleteSync();
  }

  /// Reads [oldName], writes it under [newName], deletes the old file. Fails
  /// if [newName] is already taken.
  void rename({required String oldName, required String newName}) {
    _requireName(oldName);
    _requireName(newName);
    if (oldName == newName) return;
    if (File(_pathFor(newName)).existsSync()) {
      throw ViewStoreException('A view named "$newName" already exists');
    }
    final view = load(oldName).copyWith(name: newName);
    save(view);
    delete(oldName);
  }

  /// Reads [sourceName] and writes a copy under [newName].
  void duplicate({required String sourceName, required String newName}) {
    _requireName(sourceName);
    _requireName(newName);
    if (File(_pathFor(newName)).existsSync()) {
      throw ViewStoreException('A view named "$newName" already exists');
    }
    final view = load(sourceName).copyWith(name: newName);
    save(view);
  }

  String _pathFor(String name) => p.join(viewsDirectory.path, '$name.json');

  void _requireName(String name) {
    if (!isValidName(name)) {
      throw ViewStoreException(
        'Invalid view name "$name" — must be 1-128 chars of [A-Za-z0-9 _.-]',
      );
    }
  }
}
