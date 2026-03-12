import 'dart:io';

import 'package:path/path.dart' as path;

/// Parser for build.gradle to extract product flavors
class GradleParser {
  /// Extract product flavors from build.gradle
  static Future<List<String>> getProductFlavors({
    String? projectPath,
  }) async {
    final basePath = projectPath ?? Directory.current.path;
    final buildGradlePath = path.join(basePath, 'android', 'app', 'build.gradle');
    final buildGradleKtsPath = path.join(basePath, 'android', 'app', 'build.gradle.kts');

    // Try build.gradle first, then build.gradle.kts
    File? buildGradleFile;
    if (await File(buildGradlePath).exists()) {
      buildGradleFile = File(buildGradlePath);
    } else if (await File(buildGradleKtsPath).exists()) {
      buildGradleFile = File(buildGradleKtsPath);
    }

    if (buildGradleFile == null) {
      return [];
    }

    final content = await buildGradleFile.readAsString();
    return _parseProductFlavors(content);
  }

  /// Parse product flavors from build.gradle content
  static List<String> _parseProductFlavors(String content) {
    final flavors = <String>[];

    // Remove comments
    final lines = content.split('\n');
    final cleanedLines = <String>[];
    for (final line in lines) {
      // Remove single-line comments
      var cleanLine = line;
      if (cleanLine.contains('//')) {
        cleanLine = cleanLine.substring(0, cleanLine.indexOf('//'));
      }
      cleanedLines.add(cleanLine);
    }
    final cleanedContent = cleanedLines.join('\n');

    // Remove multi-line comments
    final noComments = cleanedContent.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

    // Find productFlavors block using brace-counting
    final productFlavorsBlock = _extractBlock(noComments, 'productFlavors');
    if (productFlavorsBlock == null) return flavors;

    // Find flavor names using simple pattern
    // Pattern 1: flavorName { ... }
    final flavorPattern1 = RegExp(r'^\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\{', multiLine: true);
    for (final match in flavorPattern1.allMatches(productFlavorsBlock)) {
      final flavorName = match.group(1);
      if (flavorName != null && !flavors.contains(flavorName)) {
        flavors.add(flavorName);
      }
    }

    // Pattern 2: create("flavorName") or create('flavorName')
    final flavorPattern2 = RegExp(r'create\s*\(\s*(?:"(\w+)"|' r"'(\w+)')");
    for (final match in flavorPattern2.allMatches(productFlavorsBlock)) {
      final flavorName = match.group(1) ?? match.group(2);
      if (flavorName != null && !flavors.contains(flavorName)) {
        flavors.add(flavorName);
      }
    }

    return flavors;
  }

  /// Get application ID for a specific flavor
  static Future<String?> getApplicationId({
    String? projectPath,
    required String flavor,
  }) async {
    final basePath = projectPath ?? Directory.current.path;
    final buildGradlePath = path.join(basePath, 'android', 'app', 'build.gradle');
    final buildGradleKtsPath = path.join(basePath, 'android', 'app', 'build.gradle.kts');

    File? buildGradleFile;
    if (await File(buildGradlePath).exists()) {
      buildGradleFile = File(buildGradlePath);
    } else if (await File(buildGradleKtsPath).exists()) {
      buildGradleFile = File(buildGradleKtsPath);
    }

    if (buildGradleFile == null) {
      return null;
    }

    final content = await buildGradleFile.readAsString();
    return _parseApplicationIdForFlavor(content, flavor);
  }

  /// Parse application ID for a specific flavor
  static String? _parseApplicationIdForFlavor(String content, String flavor) {
    final flavorBlock = _extractBlock(content, flavor);
    if (flavorBlock == null) return null;

    // Find applicationId
    final appIdRegex = RegExp(r'applicationId\s+(?:[=:]\s*)?(?:"([^"]+)"|' r"'([^']+)')");
    final appIdMatch = appIdRegex.firstMatch(flavorBlock);
    if (appIdMatch != null) {
      return appIdMatch.group(1) ?? appIdMatch.group(2);
    }

    // If not found, look for applicationIdSuffix
    final appIdSuffixRegex = RegExp(r'applicationIdSuffix\s+(?:[=:]\s*)?(?:"([^"]+)"|' r"'([^']+)')");
    final appIdSuffixMatch = appIdSuffixRegex.firstMatch(flavorBlock);
    if (appIdSuffixMatch != null) {
      final suffix = appIdSuffixMatch.group(1) ?? appIdSuffixMatch.group(2);
      // Try to get default applicationId from defaultConfig
      final defaultAppId = _parseDefaultApplicationId(content);
      if (defaultAppId != null && suffix != null) {
        return '$defaultAppId$suffix';
      }
    }

    return null;
  }

  /// Parse default application ID from defaultConfig
  static String? _parseDefaultApplicationId(String content) {
    final defaultConfigBlock = _extractBlock(content, 'defaultConfig');
    if (defaultConfigBlock == null) return null;

    final appIdRegex = RegExp(r'applicationId\s+(?:[=:]\s*)?(?:"([^"]+)"|' r"'([^']+)')");
    final appIdMatch = appIdRegex.firstMatch(defaultConfigBlock);

    return appIdMatch?.group(1) ?? appIdMatch?.group(2);
  }

  /// Extract the content of a named block using brace-counting.
  /// Given `blockName { ... }`, returns the content between the braces.
  static String? _extractBlock(String content, String blockName) {
    final startRegex = RegExp(
      '(?:^|\\s)$blockName\\s*\\{',
      multiLine: true,
    );
    final match = startRegex.firstMatch(content);
    if (match == null) return null;

    // Find the opening brace position
    final openBrace = content.indexOf('{', match.start);
    if (openBrace < 0) return null;

    var depth = 1;
    var i = openBrace + 1;
    while (i < content.length && depth > 0) {
      if (content[i] == '{') {
        depth++;
      } else if (content[i] == '}') {
        depth--;
      }
      if (depth > 0) i++;
    }

    if (depth != 0) return null;
    return content.substring(openBrace + 1, i);
  }
}
