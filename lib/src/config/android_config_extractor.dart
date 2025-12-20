import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'firebase_config.dart';
import 'gradle_parser.dart';

/// Extracts Firebase configuration from google-services.json (Android)
class AndroidConfigExtractor {
  /// Extract Firebase config from google-services.json
  ///
  /// Searches for google-services.json in common locations:
  /// - android/app/google-services.json
  /// - android/app/src/{flavor}/google-services.json
  static Future<List<FirebaseConfig>> extract({String? projectPath, String? flavor}) async {
    final basePath = projectPath ?? Directory.current.path;
    final configs = <FirebaseConfig>[];

    // Get product flavors from build.gradle
    final productFlavors = await GradleParser.getProductFlavors(projectPath: basePath);

    // Try to find google-services.json files
    final searchPaths = <String>[
      path.join(basePath, 'android', 'app', 'google-services.json'),
      if (flavor != null)
        path.join(basePath, 'android', 'app', 'src', flavor, 'google-services.json'),
    ];

    // Also search for flavor-specific configs in src directory
    final srcDir = Directory(path.join(basePath, 'android', 'app', 'src'));
    if (await srcDir.exists()) {
      await for (final entity in srcDir.list()) {
        if (entity is Directory) {
          final configFile = path.join(entity.path, 'google-services.json');
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
          // Parse ALL clients from this google-services.json file
          final fileConfigs = await _parseAllClientsFromGoogleServicesJson(file, basePath);
          configs.addAll(fileConfigs);
        } catch (e) {
          print('Warning: Failed to parse $filePath: $e');
        }
      }
    }

    // Filter configs to only include those matching product flavors
    if (productFlavors.isNotEmpty) {
      return await _filterConfigsByFlavors(configs, productFlavors, basePath);
    }

    return configs;
  }

  /// Parse google-services.json file and extract all clients
  static Future<List<FirebaseConfig>> _parseAllClientsFromGoogleServicesJson(
    File file,
    String basePath,
  ) async {
    final configs = <FirebaseConfig>[];
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // Extract project info
    final projectInfo = json['project_info'] as Map<String, dynamic>?;
    if (projectInfo == null) return configs;

    final projectId = projectInfo['project_id'] as String?;
    final projectNumber = projectInfo['project_number'] as String?;
    final storageBucket = projectInfo['storage_bucket'] as String?;

    if (projectId == null || projectNumber == null) return configs;

    // Extract ALL clients (not just the first one)
    final clients = json['client'] as List<dynamic>?;
    if (clients == null || clients.isEmpty) return configs;

    // Parse each client
    for (final clientData in clients) {
      final client = clientData as Map<String, dynamic>;
      final clientInfo = client['client_info'] as Map<String, dynamic>?;
      if (clientInfo == null) continue;

      final appId = clientInfo['mobilesdk_app_id'] as String?;
      if (appId == null) continue;

      final androidClientInfo = clientInfo['android_client_info'] as Map<String, dynamic>?;
      final bundleId = androidClientInfo?['package_name'] as String?;
      if (bundleId == null) continue;

      // Try to detect environment from file path or package name
      String? environment;
      final filePath = file.path;
      final relativePath = path.relative(filePath, from: basePath);

      // Check if in flavor directory (e.g., android/app/src/dev/google-services.json)
      if (relativePath.contains('src/')) {
        final parts = relativePath.split('/');
        final srcIndex = parts.indexOf('src');
        if (srcIndex >= 0 && srcIndex + 1 < parts.length) {
          final flavorName = parts[srcIndex + 1];
          // Skip common non-flavor directories
          if (!['main', 'debug', 'release', 'androidTest', 'test'].contains(flavorName)) {
            environment = flavorName;
          }
        }
      }

      // If not found in path, try to extract from bundle ID
      if (environment == null) {
        final bundleParts = bundleId.split('.');
        final lastPart = bundleParts.last.toLowerCase();
        if (['dev', 'development', 'staging', 'qa', 'production', 'prod'].contains(lastPart)) {
          environment = lastPart == 'prod' ? 'production' : lastPart;
        } else if (lastPart == 'doitnow') {
          // If no suffix, it's likely production
          environment = 'production';
        }
      }

      configs.add(FirebaseConfig(
        projectId: projectId,
        projectNumber: projectNumber,
        appId: appId,
        bundleId: bundleId,
        platform: 'android',
        environment: environment,
        storageBucket: storageBucket,
      ));
    }

    return configs;
  }

  /// Filter configs to only include those matching product flavors
  static Future<List<FirebaseConfig>> _filterConfigsByFlavors(
    List<FirebaseConfig> allConfigs,
    List<String> productFlavors,
    String basePath,
  ) async {
    final filteredConfigs = <FirebaseConfig>[];

    if (allConfigs.isEmpty) return filteredConfigs;

    for (final flavor in productFlavors) {
      // Get the application ID for this flavor from build.gradle
      final flavorAppId = await GradleParser.getApplicationId(
        projectPath: basePath,
        flavor: flavor,
      );

      // Find matching config by bundle ID
      FirebaseConfig? matchedConfig;

      if (flavorAppId != null) {
        // Try to find exact match by bundle ID
        try {
          matchedConfig = allConfigs.firstWhere(
            (config) => config.bundleId == flavorAppId,
          );
        } catch (_) {
          // If not found by bundle ID, try by environment name
          try {
            matchedConfig = allConfigs.firstWhere(
              (config) => config.environment?.toLowerCase() == flavor.toLowerCase(),
            );
          } catch (_) {
            // No match found, skip this flavor
            continue;
          }
        }
      } else {
        // If no applicationId found, try to match by environment/flavor name
        try {
          matchedConfig = allConfigs.firstWhere(
            (config) => config.environment?.toLowerCase() == flavor.toLowerCase(),
          );
        } catch (_) {
          // No match found, skip this flavor
          continue;
        }
      }

      // Update environment to match the flavor name
      filteredConfigs.add(FirebaseConfig(
        projectId: matchedConfig.projectId,
        projectNumber: matchedConfig.projectNumber,
        appId: matchedConfig.appId,
        bundleId: matchedConfig.bundleId,
        platform: matchedConfig.platform,
        environment: flavor,
        storageBucket: matchedConfig.storageBucket,
      ));
    }

    return filteredConfigs;
  }

  /// Check if google-services.json exists
  static Future<bool> hasGoogleServicesJson({String? projectPath}) async {
    final basePath = projectPath ?? Directory.current.path;
    final file = File(path.join(basePath, 'android', 'app', 'google-services.json'));
    return await file.exists();
  }
}
