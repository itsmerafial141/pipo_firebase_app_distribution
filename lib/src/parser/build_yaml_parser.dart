import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'build_config.dart';

/// Parser for build.yaml configuration file
class BuildYamlParser {
  /// Parse build.yaml from project path
  static Future<BuildConfig?> parse({String? projectPath}) async {
    final basePath = projectPath ?? Directory.current.path;
    final buildYamlFile = File(path.join(basePath, 'build.yaml'));

    if (!await buildYamlFile.exists()) {
      return null;
    }

    final content = await buildYamlFile.readAsString();
    final yaml = loadYaml(content) as YamlMap;

    return BuildConfig.fromMap(_yamlMapToMap(yaml));
  }

  /// Check if build.yaml exists
  static Future<bool> exists({String? projectPath}) async {
    final basePath = projectPath ?? Directory.current.path;
    final buildYamlFile = File(path.join(basePath, 'build.yaml'));
    return await buildYamlFile.exists();
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
