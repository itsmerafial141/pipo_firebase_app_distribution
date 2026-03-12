import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import 'firebase_config.dart';

/// Extracts Firebase configuration from GoogleService-Info.plist (iOS)
class IosConfigExtractor {
  /// Extract Firebase config from GoogleService-Info.plist
  ///
  /// Searches for GoogleService-Info.plist in common locations:
  /// - ios/Runner/GoogleService-Info.plist
  /// - ios/Runner/Firebase/{flavor}/GoogleService-Info.plist
  static Future<List<FirebaseConfig>> extract({
    String? projectPath,
    String? flavor,
  }) async {
    final basePath = projectPath ?? Directory.current.path;
    final configs = <FirebaseConfig>[];

    // Try to find GoogleService-Info.plist files
    final searchPaths = <String>[
      path.join(basePath, 'ios', 'Runner', 'GoogleService-Info.plist'),
      if (flavor != null)
        path.join(basePath, 'ios', 'Runner', 'Firebase', flavor, 'GoogleService-Info.plist'),
    ];

    // Search for flavor-specific configs in Firebase directory
    final firebaseDir = Directory(path.join(basePath, 'ios', 'Runner', 'Firebase'));
    if (await firebaseDir.exists()) {
      await for (final entity in firebaseDir.list()) {
        if (entity is Directory) {
          final configFile = path.join(entity.path, 'GoogleService-Info.plist');
          if (!searchPaths.contains(configFile)) {
            searchPaths.add(configFile);
          }
        }
      }
    }

    // Search for flavor-specific configs directly under Runner directory
    // (e.g., ios/Runner/dev/, ios/Runner/staging/, ios/Runner/production/)
    final runnerDir = Directory(path.join(basePath, 'ios', 'Runner'));
    if (await runnerDir.exists()) {
      final skipDirs = {'Firebase', 'Assets.xcassets', 'Base.lproj'};
      await for (final entity in runnerDir.list()) {
        if (entity is Directory) {
          final dirName = path.basename(entity.path);
          if (skipDirs.contains(dirName) || dirName.startsWith('.')) continue;
          final configFile = path.join(entity.path, 'GoogleService-Info.plist');
          if (!searchPaths.contains(configFile)) {
            searchPaths.add(configFile);
          }
        }
      }
    }

    // Track which files we've already parsed to avoid duplicates
    final parsedFiles = <String>{};

    for (final filePath in searchPaths) {
      final file = File(filePath);
      if (await file.exists() && !parsedFiles.contains(filePath)) {
        parsedFiles.add(filePath);
        try {
          final config = await _parseGoogleServiceInfoPlist(file, basePath);
          if (config != null) {
            // Deduplicate by appId — prefer config with environment detected from path
            final existingIndex = configs.indexWhere((c) => c.appId == config.appId);
            if (existingIndex >= 0) {
              if (config.environment != null && configs[existingIndex].environment == null) {
                configs[existingIndex] = config;
              }
              continue;
            }
            configs.add(config);
          }
        } catch (e) {
          print('Warning: Failed to parse $filePath: $e');
        }
      }
    }

    return configs;
  }

  /// Parse GoogleService-Info.plist file
  static Future<FirebaseConfig?> _parseGoogleServiceInfoPlist(
    File file,
    String basePath,
  ) async {
    final content = await file.readAsString();
    final document = XmlDocument.parse(content);

    // Find the dict element
    final dict = document.findAllElements('dict').firstOrNull;
    if (dict == null) return null;

    // Parse plist key-value pairs
    final plistData = _parsePlistDict(dict);

    final projectId = plistData['PROJECT_ID'] as String?;
    final projectNumber = plistData['GCM_SENDER_ID'] as String?;
    final appId = plistData['GOOGLE_APP_ID'] as String?;
    final bundleId = plistData['BUNDLE_ID'] as String?;
    final storageBucket = plistData['STORAGE_BUCKET'] as String?;

    if (projectId == null || projectNumber == null || appId == null || bundleId == null) {
      return null;
    }

    // Try to detect environment from file path or bundle ID
    String? environment;
    final filePath = file.path;
    final relativePath = path.relative(filePath, from: basePath);

    // Check if in Firebase/flavor directory
    if (relativePath.contains('Firebase/')) {
      final parts = relativePath.split('/');
      final firebaseIndex = parts.indexOf('Firebase');
      if (firebaseIndex >= 0 && firebaseIndex + 1 < parts.length) {
        environment = parts[firebaseIndex + 1];
      }
    }

    // Check if in Runner/{env}/ directory (e.g., ios/Runner/dev/GoogleService-Info.plist)
    if (environment == null && relativePath.contains('Runner/')) {
      final parts = relativePath.split('/');
      final runnerIndex = parts.indexOf('Runner');
      if (runnerIndex >= 0 && runnerIndex + 1 < parts.length) {
        final candidate = parts[runnerIndex + 1];
        // Only treat as environment if it's not the plist file itself
        if (candidate != 'GoogleService-Info.plist' && candidate != 'Firebase') {
          environment = candidate;
        }
      }
    }

    // If not found in path, try to extract from bundle ID
    if (environment == null) {
      final bundleParts = bundleId.split('.');
      final lastPart = bundleParts.last.toLowerCase();
      if (['dev', 'development', 'staging', 'qa', 'production', 'prod'].contains(lastPart)) {
        environment = lastPart == 'prod' ? 'production' : lastPart;
      } else if (lastPart == 'doitnow' || lastPart == bundleParts[bundleParts.length - 2]) {
        // If no environment suffix, it's likely production
        environment = 'production';
      }
    }

    return FirebaseConfig(
      projectId: projectId,
      projectNumber: projectNumber,
      appId: appId,
      bundleId: bundleId,
      platform: 'ios',
      environment: environment,
      storageBucket: storageBucket,
    );
  }

  /// Parse plist dict element into a Map
  static Map<String, dynamic> _parsePlistDict(XmlElement dict) {
    final result = <String, dynamic>{};
    final children = dict.children.whereType<XmlElement>().toList();

    for (var i = 0; i < children.length - 1; i += 2) {
      final keyElement = children[i];
      final valueElement = children[i + 1];

      if (keyElement.name.local == 'key') {
        final key = keyElement.innerText;
        final value = _parsePlistValue(valueElement);
        result[key] = value;
      }
    }

    return result;
  }

  /// Parse plist value element
  static dynamic _parsePlistValue(XmlElement element) {
    switch (element.name.local) {
      case 'string':
        return element.innerText;
      case 'integer':
        return int.tryParse(element.innerText);
      case 'real':
        return double.tryParse(element.innerText);
      case 'true':
        return true;
      case 'false':
        return false;
      case 'dict':
        return _parsePlistDict(element);
      case 'array':
        return element.children
            .whereType<XmlElement>()
            .map(_parsePlistValue)
            .toList();
      default:
        return element.innerText;
    }
  }

  /// Check if GoogleService-Info.plist exists
  static Future<bool> hasGoogleServiceInfoPlist({String? projectPath}) async {
    final basePath = projectPath ?? Directory.current.path;
    final file = File(path.join(basePath, 'ios', 'Runner', 'GoogleService-Info.plist'));
    return await file.exists();
  }
}
