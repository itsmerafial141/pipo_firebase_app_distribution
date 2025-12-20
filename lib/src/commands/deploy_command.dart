import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

import '../builder/flutter_builder.dart';
import '../parser/build_config.dart';
import '../parser/build_yaml_parser.dart';
import '../uploader/firebase_uploader.dart';
import '../utils/error_logger.dart';
import '../utils/git_helper.dart';
import '../utils/version_manager.dart';

/// Deploy command options
class DeployCommandOptions {
  final String environment;
  final String? platform; // android, ios, or both
  final bool? skipBuild;
  final bool? skipUpload;
  final bool? skipVersionIncrement;
  final bool? skipGitTag;

  DeployCommandOptions({
    required this.environment,
    this.platform,
    this.skipBuild,
    this.skipUpload,
    this.skipVersionIncrement,
    this.skipGitTag,
  });
}

/// Deploy command to build and upload app
class DeployCommand {
  final Logger logger;
  final String? projectPath;

  DeployCommand({
    Logger? logger,
    this.projectPath,
  }) : logger = logger ?? Logger();

  /// Run the deploy command
  Future<int> run(DeployCommandOptions options) async {
    final basePath = projectPath ?? Directory.current.path;

    _printBanner();

    logger.info('🚀 Starting deployment for ${options.environment} environment');
    logger.info('');

    try {
      return await _executeDeploy(options, basePath);
    } catch (e, stackTrace) {
      logger.err('');
      logger.err('╔══════════════════════════════════════════════════════════════╗');
      logger.err('║                    ❌ DEPLOYMENT FAILED ❌                    ║');
      logger.err('╚══════════════════════════════════════════════════════════════╝');
      logger.err('');
      logger.err('💥 An unexpected error occurred:');
      logger.err('   $e');
      logger.err('');

      // Save error log
      final errorLogger = ErrorLogger(projectPath: basePath);
      final logPath = await errorLogger.logDeploymentError(
        environment: options.environment,
        error: e.toString(),
        stackTrace: stackTrace.toString(),
      );

      logger.err('📝 Error log saved to: ${errorLogger.getRelativePath(logPath)}');
      logger.err('');
      logger.info('💡 Troubleshooting:');
      logger.info('   1. Check if all requirements are installed (Flutter, Firebase CLI)');
      logger.info('   2. Verify build.yaml configuration');
      logger.info('   3. Review error log for detailed information');
      logger.info('');
      return 1;
    }
  }

  /// Execute deployment
  Future<int> _executeDeploy(DeployCommandOptions options, String basePath) async {

    // Step 1: Parse build.yaml
    logger.info('📋 Reading build configuration...');
    final buildConfig = await BuildYamlParser.parse(projectPath: basePath);

    if (buildConfig == null) {
      logger.err('❌ build.yaml not found!');
      logger.info('');
      logger.info('Run "pipo_firebase init" to generate build.yaml');
      return 1;
    }

    // Step 2: Validate environment exists
    if (!buildConfig.environments.containsKey(options.environment)) {
      logger.err('❌ Environment "${options.environment}" not found in build.yaml');
      logger.info('');
      logger.info('Available environments: ${buildConfig.environments.keys.join(", ")}');
      return 1;
    }

    final envConfig = buildConfig.environments[options.environment]!;
    logger.success('✅ Configuration loaded');
    logger.info('');

    // Step 3: Auto-increment version if needed
    String? version;
    final shouldIncrementVersion = options.skipVersionIncrement != true && envConfig.setup.autoIncrement;

    if (shouldIncrementVersion) {
      logger.info('📊 Incrementing build number...');
      final versionManager = VersionManager(projectPath: basePath);
      version = await versionManager.incrementBuildNumber();

      if (version != null) {
        logger.info('📊 Version: $version');
      } else {
        logger.warn('⚠️  Failed to increment version');
      }
      logger.info('');
    } else {
      final versionManager = VersionManager(projectPath: basePath);
      version = await versionManager.getCurrentVersion();
      logger.info('📊 Version: $version');
      logger.info('');
    }

    // Step 4: Determine platforms to build
    final platforms = _determinePlatforms(
      requested: options.platform,
      envConfig: envConfig,
    );

    if (platforms.isEmpty) {
      logger.err('❌ No platforms to build');
      return 1;
    }

    logger.info('📱 Platforms: ${platforms.join(", ")}');
    logger.info('');

    // Step 5: Build artifacts
    final artifactPaths = <String, String>{};

    if (options.skipBuild != true) {
      _printSectionHeader('BUILD PHASE');
      logger.info('');

      for (final platform in platforms) {
        logger.info('╭─────────────────────────────────────────────────────────────╮');
        logger.info('│  🔨 Building ${platform.toUpperCase()}                       │');
        logger.info('╰─────────────────────────────────────────────────────────────╯');
        logger.info('');

        try {
          final buildResult = await _buildPlatform(
            platform: platform,
            environment: options.environment,
            envConfig: envConfig,
            buildConfig: buildConfig,
          );

          if (!buildResult.success) {
            logger.err('');
            logger.err('╔══════════════════════════════════════════════════════════════╗');
            logger.err('║                  ❌ BUILD FAILED ❌                           ║');
            logger.err('╚══════════════════════════════════════════════════════════════╝');
            logger.err('');
            logger.err('Platform: $platform');
            if (buildResult.error != null) {
              logger.err('Error: ${buildResult.error}');
            }
            logger.err('');

            // Save error log
            final errorLogger = ErrorLogger(projectPath: basePath);
            final logPath = await errorLogger.logBuildError(
              platform: platform,
              environment: options.environment,
              buildMode: envConfig.setup.buildMode,
              error: buildResult.error ?? 'Build failed',
              buildOutput: buildResult.buildOutput,
            );

            logger.err('📝 Error log saved to: ${errorLogger.getRelativePath(logPath)}');
            logger.err('');
            logger.info('💡 Common issues:');
            logger.info('   - Check Flutter SDK installation');
            logger.info('   - Verify flavor configuration in build.gradle');
            logger.info('   - Check error log for detailed information');
            logger.info('');
            return 1;
          }

          if (buildResult.artifactPath != null) {
            artifactPaths[platform] = buildResult.artifactPath!;
          }

          logger.info('');
        } catch (e, stackTrace) {
          logger.err('');
          logger.err('❌ Build crashed for $platform');
          logger.err('Error: $e');
          logger.detail('Stack trace: $stackTrace');
          logger.err('');

          // Save error log
          final errorLogger = ErrorLogger(projectPath: basePath);
          final logPath = await errorLogger.logBuildError(
            platform: platform,
            environment: options.environment,
            buildMode: envConfig.setup.buildMode,
            error: e.toString(),
            stackTrace: stackTrace.toString(),
          );

          logger.err('📝 Error log saved to: ${errorLogger.getRelativePath(logPath)}');
          logger.err('');
          return 1;
        }
      }

      logger.success('✅ All builds completed successfully!');
      logger.info('');
    } else {
      logger.info('⏭️  Skipping build phase');
      logger.info('');
    }

    // Step 6: Generate release notes
    String? releaseNotes;
    final gitHelper = GitHelper(projectPath: basePath);
    if (await gitHelper.isGitRepository()) {
      logger.info('📝 Generating release notes...');
      releaseNotes = await gitHelper.generateReleaseNotes(
        version: version ?? 'unknown',
        environment: options.environment,
        buildMode: envConfig.setup.buildMode,
      );
      logger.success('✅ Release notes generated');
      logger.info('');
    }

    // Step 7: Upload to Firebase
    if (options.skipUpload != true && envConfig.setup.upload) {
      _printSectionHeader('UPLOAD PHASE');
      logger.info('');

      for (final platform in platforms) {
        final artifactPath = artifactPaths[platform];
        if (artifactPath == null) {
          logger.warn('⚠️  No artifact found for $platform, skipping upload');
          continue;
        }

        final appId = platform == 'android' ? envConfig.androidAppId : envConfig.iosAppId;

        if (appId == null) {
          logger.warn('⚠️  No App ID configured for $platform, skipping upload');
          continue;
        }

        logger.info('╭─────────────────────────────────────────────────────────────╮');
        logger.info('│  ☁️  Uploading ${platform.toUpperCase()} to Firebase         │');
        logger.info('╰─────────────────────────────────────────────────────────────╯');
        logger.info('');

        try {
          final uploadResult = await _uploadToFirebase(
            artifactPath: artifactPath,
            appId: appId,
            releaseNotes: releaseNotes,
            groups: envConfig.group,
            projectId: buildConfig.firebase.projectId,
            timeout: buildConfig.firebase.timeout,
          );

          if (!uploadResult.success) {
            logger.err('');
            logger.err('╔══════════════════════════════════════════════════════════════╗');
            logger.err('║                  ❌ UPLOAD FAILED ❌                          ║');
            logger.err('╚══════════════════════════════════════════════════════════════╝');
            logger.err('');
            logger.err('Platform: $platform');
            if (uploadResult.error != null) {
              logger.err('Error: ${uploadResult.error}');
            }
            logger.err('');

            // Save error log
            final errorLogger = ErrorLogger(projectPath: basePath);
            final logPath = await errorLogger.logUploadError(
              platform: platform,
              environment: options.environment,
              appId: appId,
              artifactPath: artifactPath,
              error: uploadResult.error ?? 'Upload failed',
              firebaseOutput: uploadResult.firebaseOutput,
            );

            logger.err('📝 Error log saved to: ${errorLogger.getRelativePath(logPath)}');
            logger.err('');
            logger.info('💡 Common issues:');
            logger.info('   - Check Firebase CLI installation (npm install -g firebase-tools)');
            logger.info('   - Verify Firebase token is set (FIREBASE_TOKEN env var)');
            logger.info('   - Check Firebase project ID and App ID');
            logger.info('   - Verify network connection');
            logger.info('');
            return 1;
          }

          logger.info('');
        } catch (e, stackTrace) {
          logger.err('');
          logger.err('❌ Upload crashed for $platform');
          logger.err('Error: $e');
          logger.detail('Stack trace: $stackTrace');
          logger.err('');

          // Save error log
          final errorLogger = ErrorLogger(projectPath: basePath);
          final logPath = await errorLogger.logUploadError(
            platform: platform,
            environment: options.environment,
            appId: appId,
            artifactPath: artifactPath,
            error: e.toString(),
            stackTrace: stackTrace.toString(),
          );

          logger.err('📝 Error log saved to: ${errorLogger.getRelativePath(logPath)}');
          logger.err('');
          return 1;
        }
      }

      logger.success('✅ All uploads completed successfully!');
      logger.info('');
    } else {
      logger.info('⏭️  Skipping upload to Firebase');
      logger.info('');
    }

    // Step 8: Git tagging
    if (options.skipGitTag != true && await gitHelper.isGitRepository()) {
      logger.info('🏷️  Creating git tags...');

      if (version != null) {
        // Create version tag
        final versionTag = 'appdist-${options.environment}-$version';
        await gitHelper.createTag(
          tagName: versionTag,
          message: 'Firebase App Distribution $version (${options.environment})',
        );

        // Create/move latest tag
        await gitHelper.createLatestTag(
          environment: options.environment,
          version: version,
        );

        // Push tags
        await gitHelper.pushTag(tagName: versionTag);
        await gitHelper.pushTag(tagName: 'appdist-${options.environment}-latest', force: true);

        logger.success('✅ Git tags created and pushed');
      }

      // Commit version changes if incremented
      if (shouldIncrementVersion && version != null) {
        final committed = await gitHelper.commit(
          files: ['pubspec.yaml'],
          message: 'build: bump version to $version for ${options.environment} environment',
        );

        if (committed) {
          await gitHelper.pushCommits();
          logger.success('✅ Version changes committed and pushed');
        }
      }

      logger.info('');
    }

    // Success summary
    _printSuccessSummary(
      environment: options.environment,
      version: version,
      platforms: platforms,
      uploaded: options.skipUpload != true && envConfig.setup.upload,
    );

    return 0;
  }

  /// Build platform
  Future<BuildResult> _buildPlatform({
    required String platform,
    required String environment,
    required EnvironmentConfig envConfig,
    required BuildConfig buildConfig,
  }) async {
    final builder = FlutterBuilder(
      projectPath: projectPath,
      logger: logger,
    );

    final buildFormat = platform == 'android'
        ? buildConfig.platforms.android.buildFormat
        : 'ipa';

    final buildOptions = BuildOptions(
      environment: environment,
      buildMode: envConfig.setup.buildMode,
      platform: platform,
      buildFormat: buildFormat,
      obfuscate: envConfig.setup.obfuscate,
      clean: envConfig.setup.clean,
    );

    return await builder.build(buildOptions);
  }

  /// Upload to Firebase
  Future<UploadResult> _uploadToFirebase({
    required String artifactPath,
    required String appId,
    String? releaseNotes,
    String? groups,
    required String projectId,
    required int timeout,
  }) async {
    final uploader = FirebaseUploader(
      projectPath: projectPath,
      logger: logger,
    );

    // Check for Firebase token
    String? token = Platform.environment['FIREBASE_TOKEN'];
    token ??= await uploader.loadFirebaseToken();

    final uploadOptions = UploadOptions(
      artifactPath: artifactPath,
      appId: appId,
      releaseNotes: releaseNotes,
      groups: groups,
      projectId: projectId,
      token: token,
      timeout: timeout,
    );

    return await uploader.upload(uploadOptions);
  }

  /// Determine which platforms to build
  List<String> _determinePlatforms({
    String? requested,
    required EnvironmentConfig envConfig,
  }) {
    if (requested == 'both' || requested == null) {
      final platforms = <String>[];
      if (envConfig.androidAppId != null) platforms.add('android');
      if (envConfig.iosAppId != null) platforms.add('ios');
      return platforms;
    } else if (requested == 'android' && envConfig.androidAppId != null) {
      return ['android'];
    } else if (requested == 'ios' && envConfig.iosAppId != null) {
      return ['ios'];
    }
    return [];
  }

  /// Print banner
  void _printBanner() {
    print('''
╔══════════════════════════════════════════════════════════════╗
║        🚀 Pipo Firebase App Distribution Deploy 🚀            ║
║        Build & Upload to Firebase App Distribution           ║
╚══════════════════════════════════════════════════════════════╝
''');
  }

  /// Print section header
  void _printSectionHeader(String title) {
    logger.info('');
    logger.info('═══════════════════════════════════════════════════════════════');
    logger.info('  $title');
    logger.info('═══════════════════════════════════════════════════════════════');
  }

  /// Print success summary
  void _printSuccessSummary({
    required String environment,
    String? version,
    required List<String> platforms,
    required bool uploaded,
  }) {
    logger.info('');
    logger.success('╔══════════════════════════════════════════════════════════════╗');
    logger.success('║                   🎉 DEPLOYMENT COMPLETE 🎉                   ║');
    logger.success('╚══════════════════════════════════════════════════════════════╝');
    logger.info('');
    logger.info('📊 Deployment Summary:');
    logger.info('   Environment:     $environment');
    if (version != null) {
      logger.info('   Version:         $version');
    }
    logger.info('   Platforms:       ${platforms.join(", ")}');
    logger.info('   Uploaded:        ${uploaded ? "✅ Yes" : "❌ No"}');
    logger.info('');

    if (uploaded) {
      logger.info('🔗 Next Steps:');
      logger.info('   1. Check Firebase Console for distribution links');
      logger.info('   2. Share download links with testers');
      logger.info('   3. Monitor crash reports and feedback');
      logger.info('');
    }
  }
}
