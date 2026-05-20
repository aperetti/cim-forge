import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _settingsFileName = 'settings.json';
const maxRecentProjects = 16;

class WindowGeometry {
  const WindowGeometry({required this.width, required this.height});

  final double width;
  final double height;

  Map<String, Object?> toJson() => {'width': width, 'height': height};

  static WindowGeometry? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final w = raw['width'];
    final h = raw['height'];
    if (w is! num || h is! num) return null;
    return WindowGeometry(width: w.toDouble(), height: h.toDouble());
  }
}

class UserSettings {
  UserSettings({
    List<String> recentProjects = const [],
    this.lastWindow,
  }) : _recentProjects = List.of(recentProjects);

  factory UserSettings.fromJson(Map<String, Object?> json) {
    final recents = json['recentProjects'];
    final list = recents is List
        ? recents.whereType<String>().toList()
        : <String>[];
    return UserSettings(
      recentProjects: list,
      lastWindow: WindowGeometry.fromJson(json['lastWindow']),
    );
  }

  final List<String> _recentProjects;
  WindowGeometry? lastWindow;

  List<String> get recentProjects => List.unmodifiable(_recentProjects);

  /// Adds [path] to the front of the recent list, deduplicating and bounding
  /// by [maxRecentProjects].
  void touchRecentProject(String path) {
    _recentProjects
      ..remove(path)
      ..insert(0, path);
    if (_recentProjects.length > maxRecentProjects) {
      _recentProjects.removeRange(maxRecentProjects, _recentProjects.length);
    }
  }

  Map<String, Object?> toJson() => {
    'recentProjects': _recentProjects,
    'lastWindow': lastWindow?.toJson(),
  };
}

/// Loads and persists [UserSettings] under the OS user-data directory.
///
/// Tests can pass a custom directory to the constructor to avoid touching
/// the real user-data location.
class SettingsStore {
  SettingsStore({Directory? directory}) : _injectedDirectory = directory;

  final Directory? _injectedDirectory;

  Future<Directory> _directory() async =>
      _injectedDirectory ?? await getApplicationSupportDirectory();

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _settingsFileName));

  Future<UserSettings> load() async {
    final file = await _file();
    if (!file.existsSync()) return UserSettings();
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, Object?>) return UserSettings();
      return UserSettings.fromJson(raw);
    } on Object {
      // Corrupt settings — start fresh rather than blocking app launch.
      return UserSettings();
    }
  }

  Future<void> save(UserSettings settings) async {
    final dir = await _directory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = await _file();
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
