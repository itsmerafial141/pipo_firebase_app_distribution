import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Reads and parses pubspec.yaml file
class PubspecReader {
  /// Read pubspec.yaml from project path
  static Future<Map<String, dynamic>?> read({String? projectPath}) async {
    final basePath = projectPath ?? Directory.current.path;
    final pubspecFile = File(path.join(basePath, 'pubspec.yaml'));

    if (!await pubspecFile.exists()) {
      return null;
    }

    final content = await pubspecFile.readAsString();
    final yaml = loadYaml(content) as YamlMap;

    return _yamlMapToMap(yaml);
  }

  /// Get project name from pubspec.yaml
  static Future<String?> getProjectName({String? projectPath}) async {
    final pubspec = await read(projectPath: projectPath);
    return pubspec?['name'] as String?;
  }

  /// Get project version from pubspec.yaml
  static Future<String?> getProjectVersion({String? projectPath}) async {
    final pubspec = await read(projectPath: projectPath);
    return pubspec?['version'] as String?;
  }

  /// Convert YamlMap to regular Map
  static Map<String, dynamic> _yamlMapToMap(YamlMap yamlMap) {
    final map = <String, dynamic>{};
    for (final entry in yamlMap.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      map[key] = _convertYamlValue(value);
    }
    return map;
  }

  /// Convert YAML value to regular Dart value
  static dynamic _convertYamlValue(dynamic value) {
    if (value is YamlMap) {
      return _yamlMapToMap(value);
    } else if (value is YamlList) {
      return value.map(_convertYamlValue).toList();
    } else {
      return value;
    }
  }
}
