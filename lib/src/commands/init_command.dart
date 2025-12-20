import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../config/android_config_extractor.dart';
import '../config/firebase_config.dart';
import '../config/ios_config_extractor.dart';
import '../templates/build_yaml_template.dart';
import '../utils/pubspec_reader.dart';

/// Initialize Firebase App Distribution configuration
class InitCommand {
  final Logger logger;
  final String? projectPath;

  InitCommand({
    Logger? logger,
    this.projectPath,
  }) : logger = logger ?? Logger();

  /// Run the init command
  Future<int> run() async {
    final basePath = projectPath ?? Directory.current.path;

    logger.info('🔍 Initializing Firebase App Distribution configuration...');
    logger.info('');

    // Check if build.yaml already exists
    final buildYamlFile = File(path.join(basePath, 'build.yaml'));
    if (await buildYamlFile.exists()) {
      final overwrite = logger.confirm(
        '⚠️  build.yaml already exists. Overwrite?',
        defaultValue: false,
      );

      if (!overwrite) {
        logger.info('❌ Initialization cancelled.');
        return 1;
      }
    }

    // Step 1: Extract Android configs
    final progress = logger.progress('📱 Scanning for Firebase configurations');

    final androidConfigs = await AndroidConfigExtractor.extract(
      projectPath: basePath,
    );

    // Step 2: Extract iOS configs
    final iosConfigs = await IosConfigExtractor.extract(
      projectPath: basePath,
    );

    progress.complete('✅ Firebase configurations scanned');

    // Combine all configs
    final allConfigs = <FirebaseConfig>[...androidConfigs, ...iosConfigs];

    if (allConfigs.isEmpty) {
      logger.err('❌ No Firebase configuration files found!');
      logger.info('');
      logger.info('Expected files:');
      logger.info('  Android: android/app/google-services.json');
      logger.info('  iOS: ios/Runner/GoogleService-Info.plist');
      logger.info('');
      logger.info('Please add Firebase configuration files and try again.');
      return 1;
    }

    // Display found configurations
    logger.info('');
    logger.info('📋 Found Firebase configurations:');
    logger.info('');

    for (final config in allConfigs) {
      final envLabel = config.environment != null ? ' (${config.environment})' : '';
      logger.info('  ${_getPlatformEmoji(config.platform)} ${config.platform.toUpperCase()}$envLabel');
      logger.detail('     App ID: ${config.appId}');
      logger.detail('     Bundle ID: ${config.bundleId}');
      logger.detail('     Project: ${config.projectId}');
      logger.info('');
    }

    // Step 3: Read pubspec.yaml for project info
    final projectName = await PubspecReader.getProjectName(projectPath: basePath);
    final projectVersion = await PubspecReader.getProjectVersion(projectPath: basePath);

    // Step 4: Generate build.yaml
    final generatingProgress = logger.progress('⚙️  Generating build.yaml');

    final buildYamlContent = BuildYamlTemplate.generate(
      configs: allConfigs,
      projectName: projectName,
      projectVersion: projectVersion,
    );

    await buildYamlFile.writeAsString(buildYamlContent);

    generatingProgress.complete('✅ build.yaml generated successfully');

    // Success message
    logger.info('');
    logger.success('🎉 Firebase App Distribution initialized successfully!');
    logger.info('');
    logger.info('📄 Generated file: ${path.relative(buildYamlFile.path, from: basePath)}');
    logger.info('');
    logger.info('Next steps:');
    logger.info('  1. Review and customize build.yaml');
    logger.info('  2. Run build command to test the configuration');
    logger.info('  3. Upload to Firebase App Distribution');
    logger.info('');
    logger.info('📚 Documentation: https://pub.dev/packages/pipo_firebase_app_distribution');

    return 0;
  }

  /// Get platform emoji
  String _getPlatformEmoji(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return '🤖';
      case 'ios':
        return '🍎';
      default:
        return '📱';
    }
  }
}
