import 'dart:io';

import 'package:path/path.dart' as path;

/// Manages version in pubspec.yaml
class VersionManager {
  final String? projectPath;

  VersionManager({this.projectPath});

  /// Get current version from pubspec.yaml
  Future<String?> getCurrentVersion() async {
    final basePath = projectPath ?? Directory.current.path;
    final pubspecFile = File(path.join(basePath, 'pubspec.yaml'));

    if (!await pubspecFile.exists()) {
      return null;
    }

    final content = await pubspecFile.readAsString();
    final versionLine = content.split('\n').firstWhere(
          (line) => line.trim().startsWith('version:'),
          orElse: () => '',
        );

    if (versionLine.isEmpty) return null;

    final version = versionLine.split(':')[1].trim();
    return version;
  }

  /// Increment build number
  /// Example: 1.0.0+1 -> 1.0.0+2
  Future<String?> incrementBuildNumber() async {
    final currentVersion = await getCurrentVersion();
    if (currentVersion == null) return null;

    final parts = currentVersion.split('+');
    if (parts.length != 2) {
      throw Exception('Invalid version format. Expected format: x.x.x+x');
    }

    final versionPart = parts[0];
    final buildPart = int.parse(parts[1]);
    final newBuild = buildPart + 1;
    final newVersion = '$versionPart+$newBuild';

    await _updateVersion(newVersion);
    return newVersion;
  }

  /// Increment minor version
  /// Example: 1.0.0+1 -> 1.1.0+1
  Future<String?> incrementMinorVersion() async {
    final currentVersion = await getCurrentVersion();
    if (currentVersion == null) return null;

    final parts = currentVersion.split('+');
    final versionPart = parts[0];
    final buildPart = parts.length > 1 ? parts[1] : '1';

    final versionNumbers = versionPart.split('.');
    if (versionNumbers.length != 3) {
      throw Exception('Invalid version format. Expected format: x.x.x');
    }

    final major = int.parse(versionNumbers[0]);
    final minor = int.parse(versionNumbers[1]);
    final newMinor = minor + 1;

    final newVersion = '$major.$newMinor.0+$buildPart';
    await _updateVersion(newVersion);
    return newVersion;
  }

  /// Increment major version
  /// Example: 1.0.0+1 -> 2.0.0+1
  Future<String?> incrementMajorVersion() async {
    final currentVersion = await getCurrentVersion();
    if (currentVersion == null) return null;

    final parts = currentVersion.split('+');
    final versionPart = parts[0];
    final buildPart = parts.length > 1 ? parts[1] : '1';

    final versionNumbers = versionPart.split('.');
    if (versionNumbers.length != 3) {
      throw Exception('Invalid version format. Expected format: x.x.x');
    }

    final major = int.parse(versionNumbers[0]);
    final newMajor = major + 1;

    final newVersion = '$newMajor.0.0+$buildPart';
    await _updateVersion(newVersion);
    return newVersion;
  }

  /// Update version in pubspec.yaml
  Future<void> _updateVersion(String newVersion) async {
    final basePath = projectPath ?? Directory.current.path;
    final pubspecFile = File(path.join(basePath, 'pubspec.yaml'));

    if (!await pubspecFile.exists()) {
      throw Exception('pubspec.yaml not found');
    }

    final content = await pubspecFile.readAsString();
    final lines = content.split('\n');

    final newLines = lines.map((line) {
      if (line.trim().startsWith('version:')) {
        return 'version: $newVersion';
      }
      return line;
    }).toList();

    await pubspecFile.writeAsString(newLines.join('\n'));
  }

  /// Parse version string into components
  static Map<String, dynamic> parseVersion(String version) {
    final parts = version.split('+');
    final versionPart = parts[0];
    final buildPart = parts.length > 1 ? parts[1] : '1';

    final versionNumbers = versionPart.split('.');
    if (versionNumbers.length != 3) {
      throw Exception('Invalid version format. Expected format: x.x.x+x');
    }

    return {
      'major': int.parse(versionNumbers[0]),
      'minor': int.parse(versionNumbers[1]),
      'patch': int.parse(versionNumbers[2]),
      'build': int.parse(buildPart),
      'full': version,
    };
  }
}
