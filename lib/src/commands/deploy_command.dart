import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../auth/firebase_auth.dart';
import '../builder/flutter_builder.dart';
import '../parser/build_config.dart';
import '../parser/build_yaml_parser.dart';
import '../uploader/firebase_uploader.dart';
import '../utils/deploy_logger.dart';
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
    final deployLogger = DeployLogger(projectPath: basePath);

    _printBanner();

    // Start deploy log session
    await deployLogger.start(
      environment: options.environment,
      platform: options.platform,
    );

    logger.info('🚀 Starting deployment for ${options.environment} environment');
    logger.info('📝 Log file: ${deployLogger.relativeLogPath}');
    logger.info('   Monitor with: tail -f ${deployLogger.relativeLogPath}');
    logger.info('');

    try {
      final result = await _executeDeploy(options, basePath, deployLogger);

      if (result != 0) {
        deployLogger.complete(
          success: false,
          environment: options.environment,
        );
      }

      await deployLogger.close();

      if (result != 0) {
        logger.err('📝 Full log: ${deployLogger.relativeLogPath}');
      }

      return result;
    } catch (e, stackTrace) {
      logger.err('');
      logger.err('╔══════════════════════════════════════════════════════════════╗');
      logger.err('║                    ❌ DEPLOYMENT FAILED ❌                    ║');
      logger.err('╚══════════════════════════════════════════════════════════════╝');
      logger.err('');
      logger.err('💥 An unexpected error occurred:');
      logger.err('   $e');
      logger.err('');

      deployLogger.errorDetail(
        title: 'DEPLOYMENT FAILED',
        errorMessage: e.toString(),
        stackTrace: stackTrace.toString(),
        troubleshootingTips: [
          'Check if Flutter SDK is installed',
          'Verify build.yaml configuration and credentials file',
          'Review the full log for detailed information',
        ],
      );
      deployLogger.complete(
        success: false,
        environment: options.environment,
      );
      await deployLogger.close();

      logger.err('📝 Full log: ${deployLogger.relativeLogPath}');
      logger.err('');
      logger.info('💡 Troubleshooting:');
      logger.info('   1. Check if Flutter SDK is installed');
      logger.info('   2. Verify build.yaml configuration and credentials file');
      logger.info('   3. Review full log: cat ${deployLogger.relativeLogPath}');
      logger.info('');
      return 1;
    }
  }

  /// Execute deployment
  Future<int> _executeDeploy(
    DeployCommandOptions options,
    String basePath,
    DeployLogger deployLogger,
  ) async {
    // Step 1: Parse build.yaml
    deployLogger.step('READING CONFIGURATION');
    logger.info('📋 Reading build configuration...');
    deployLogger.info('Parsing build.yaml...');

    final buildConfig = await BuildYamlParser.parse(projectPath: basePath);

    if (buildConfig == null) {
      logger.err('❌ build.yaml not found!');
      logger.info('');
      logger.info('Run "pipo_firebase init" to generate build.yaml');
      deployLogger.error('build.yaml not found');
      return 1;
    }

    // Step 2: Validate environment exists
    if (!buildConfig.environments.containsKey(options.environment)) {
      logger.err('❌ Environment "${options.environment}" not found in build.yaml');
      logger.info('');
      logger.info('Available environments: ${buildConfig.environments.keys.join(", ")}');
      deployLogger.error(
        'Environment "${options.environment}" not found. '
        'Available: ${buildConfig.environments.keys.join(", ")}',
      );
      return 1;
    }

    final envConfig = buildConfig.environments[options.environment]!;
    logger.success('✅ Configuration loaded');
    logger.info('');
    deployLogger.success('Configuration loaded');

    // Step 3: Auto-increment version if needed
    deployLogger.step('VERSION MANAGEMENT');
    String? version;
    final shouldIncrementVersion =
        options.skipVersionIncrement != true &&
        options.skipBuild != true &&
        envConfig.setup.autoIncrement;

    if (shouldIncrementVersion) {
      logger.info('📊 Incrementing build number...');
      deployLogger.info('Incrementing build number...');
      final versionManager = VersionManager(projectPath: basePath);
      version = await versionManager.incrementBuildNumber();

      if (version != null) {
        logger.info('📊 Version: $version');
        deployLogger.success('Version incremented to: $version');
      } else {
        logger.warn('⚠️  Failed to increment version');
        deployLogger.warn('Failed to increment version');
      }
      logger.info('');
    } else {
      final versionManager = VersionManager(projectPath: basePath);
      version = await versionManager.getCurrentVersion();
      logger.info('📊 Version: $version');
      deployLogger.info('Current version: $version');
      logger.info('');
    }

    // Step 4: Determine platforms to build
    final platforms = _determinePlatforms(
      requested: options.platform,
      envConfig: envConfig,
    );

    if (platforms.isEmpty) {
      logger.err('❌ No platforms to build');
      deployLogger.error('No platforms to build');
      return 1;
    }

    logger.info('📱 Platforms: ${platforms.join(", ")}');
    logger.info('');
    deployLogger.info('Platforms: ${platforms.join(", ")}');

    // Step 5: Generate release notes (before build/upload cycle)
    String? releaseNotes;
    final gitHelper = GitHelper(projectPath: basePath);
    if (await gitHelper.isGitRepository()) {
      deployLogger.step('RELEASE NOTES');
      logger.info('📝 Generating release notes...');
      deployLogger.info('Generating release notes from git history...');

      releaseNotes = await gitHelper.generateReleaseNotes(
        version: version ?? 'unknown',
        environment: options.environment,
        buildMode: envConfig.setup.buildMode,
      );
      logger.success('✅ Release notes generated');
      logger.info('');
      deployLogger.success('Release notes generated');
    }

    // Step 6: Build and upload per platform
    final shouldUpload = options.skipUpload != true && envConfig.setup.upload;

    for (final platform in platforms) {
      String? artifactPath;

      // --- BUILD ---
      if (options.skipBuild == true) {
        // When skipping build, try to find an existing artifact
        artifactPath = _findExistingArtifact(
          platform: platform,
          environment: options.environment,
          envConfig: envConfig,
          buildConfig: buildConfig,
          basePath: basePath,
        );

        if (artifactPath != null) {
          logger.info('📦 Found existing artifact: ${artifactPath.split('/').last}');
          deployLogger.info('Found existing artifact: $artifactPath');
        } else {
          logger.warn('⚠️  No existing artifact found for $platform');
          deployLogger.warn('No existing artifact found for $platform');
        }
        logger.info('');
      } else {
        deployLogger.step('BUILD ${platform.toUpperCase()}');
        _printSectionHeader('BUILD ${platform.toUpperCase()}');
        logger.info('');

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
            deployLogger: deployLogger,
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

            deployLogger.errorDetail(
              title: 'BUILD FAILED ($platform)',
              errorMessage: buildResult.error ?? 'Build failed',
              output: buildResult.buildOutput,
              troubleshootingTips: [
                'Check Flutter SDK installation: flutter doctor',
                'Verify flavor configuration in build.gradle',
                'Clean and rebuild: flutter clean && flutter pub get',
                'Check for missing dependencies in pubspec.yaml',
                'Verify Firebase configuration files are present',
              ],
            );

            logger.info('💡 Common issues:');
            logger.info('   - Check Flutter SDK installation');
            logger.info('   - Verify flavor configuration in build.gradle');
            logger.info('   - Check full log: cat ${deployLogger.relativeLogPath}');
            logger.info('');
            return 1;
          }

          artifactPath = buildResult.artifactPath;
          logger.success('✅ Build completed for ${platform.toUpperCase()}');
          logger.info('');
        } catch (e, stackTrace) {
          logger.err('');
          logger.err('❌ Build crashed for $platform');
          logger.err('Error: $e');
          logger.detail('Stack trace: $stackTrace');
          logger.err('');

          deployLogger.errorDetail(
            title: 'BUILD CRASHED ($platform)',
            errorMessage: e.toString(),
            stackTrace: stackTrace.toString(),
            troubleshootingTips: [
              'Check Flutter SDK installation: flutter doctor',
              'Verify flavor configuration in build.gradle',
              'Clean and rebuild: flutter clean && flutter pub get',
            ],
          );

          return 1;
        }
      }

      // --- UPLOAD ---
      if (shouldUpload) {
        if (artifactPath == null) {
          logger.warn('⚠️  No artifact found for $platform, skipping upload');
          deployLogger.warn('No artifact found for $platform, skipping upload');
          continue;
        }

        final appId = platform == 'android' ? envConfig.androidAppId : envConfig.iosAppId;

        if (appId == null) {
          logger.warn('⚠️  No App ID configured for $platform, skipping upload');
          deployLogger.warn('No App ID configured for $platform, skipping upload');
          continue;
        }

        deployLogger.step('UPLOAD ${platform.toUpperCase()}');
        _printSectionHeader('UPLOAD ${platform.toUpperCase()}');
        logger.info('');

        logger.info('╭─────────────────────────────────────────────────────────────╮');
        logger.info('│  ☁️  Uploading ${platform.toUpperCase()} to Firebase         │');
        logger.info('╰─────────────────────────────────────────────────────────────╯');
        logger.info('');

        deployLogger.info('Uploading to Firebase App Distribution...');
        deployLogger.info('App ID: $appId');
        deployLogger.info('Artifact: $artifactPath');
        if (envConfig.groupsString != null) {
          deployLogger.info('Groups: ${envConfig.groupsString}');
        }

        try {
          final uploadResult = await _uploadToFirebase(
            artifactPath: artifactPath,
            appId: appId,
            releaseNotes: releaseNotes,
            groups: envConfig.groupsString,
            projectNumber: buildConfig.firebase.projectNumber,
            credentialsFile: buildConfig.firebase.credentialsFile,
            timeout: buildConfig.firebase.timeout,
            deployLogger: deployLogger,
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

            deployLogger.errorDetail(
              title: 'UPLOAD FAILED ($platform)',
              errorMessage: uploadResult.error ?? 'Upload failed',
              output: uploadResult.firebaseOutput,
              troubleshootingTips: [
                'Check service account credentials file',
                'Verify project number and App ID in build.yaml',
                'Ensure service account has Firebase App Distribution Admin role',
                'Verify network connection',
              ],
            );

            logger.info('💡 Common issues:');
            logger.info('   - Check service account credentials file');
            logger.info('   - Verify project number and App ID in build.yaml');
            logger.info('   - Ensure service account has Firebase App Distribution Admin role');
            logger.info('   - Verify network connection');
            logger.info('');
            return 1;
          }

          logger.success('✅ Upload completed for ${platform.toUpperCase()}');
          logger.info('');
          deployLogger.success('Upload completed for ${platform.toUpperCase()}');
        } catch (e, stackTrace) {
          logger.err('');
          logger.err('❌ Upload crashed for $platform');
          logger.err('Error: $e');
          logger.detail('Stack trace: $stackTrace');
          logger.err('');

          deployLogger.errorDetail(
            title: 'UPLOAD CRASHED ($platform)',
            errorMessage: e.toString(),
            stackTrace: stackTrace.toString(),
            troubleshootingTips: [
              'Check service account credentials file',
              'Verify network connection',
              'Try increasing timeout in build.yaml',
            ],
          );

          return 1;
        }
      }
    }

    if (options.skipBuild == true) {
      logger.info('⏭️  Skipping build phase');
      logger.info('');
      deployLogger.info('Skipping build phase (--skip-build)');
    }
    if (!shouldUpload) {
      logger.info('⏭️  Skipping upload to Firebase');
      logger.info('');
      deployLogger.info('Skipping upload (--skip-upload or upload=false in config)');
    }

    // Step 8: Git tagging
    if (options.skipGitTag != true && await gitHelper.isGitRepository()) {
      deployLogger.step('GIT TAGGING');
      logger.info('🏷️  Creating git tags...');
      deployLogger.info('Creating git tags...');

      if (version != null) {
        // Create version tag
        final versionTag = 'appdist-${options.environment}-$version';
        await gitHelper.createTag(
          tagName: versionTag,
          message: 'Firebase App Distribution $version (${options.environment})',
        );
        deployLogger.info('Created tag: $versionTag');

        // Create/move latest tag
        await gitHelper.createLatestTag(
          environment: options.environment,
          version: version,
        );
        deployLogger.info('Updated latest tag: appdist-${options.environment}-latest');

        // Push tags
        await gitHelper.pushTag(tagName: versionTag);
        await gitHelper.pushTag(tagName: 'appdist-${options.environment}-latest', force: true);
        deployLogger.success('Git tags created and pushed');

        logger.success('✅ Git tags created and pushed');
      }

      // Commit version changes if incremented
      if (shouldIncrementVersion && version != null) {
        deployLogger.info('Committing version changes...');
        final committed = await gitHelper.commit(
          files: ['pubspec.yaml'],
          message: 'build: bump version to $version for ${options.environment} environment',
        );

        if (committed) {
          await gitHelper.pushCommits();
          logger.success('✅ Version changes committed and pushed');
          deployLogger.success('Version changes committed and pushed');
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

    deployLogger.complete(
      success: true,
      environment: options.environment,
      version: version,
      platforms: platforms,
      uploaded: options.skipUpload != true && envConfig.setup.upload,
    );

    logger.info('📝 Full log: ${deployLogger.relativeLogPath}');
    logger.info('');

    return 0;
  }

  /// Build platform
  Future<BuildResult> _buildPlatform({
    required String platform,
    required String environment,
    required EnvironmentConfig envConfig,
    required BuildConfig buildConfig,
    required DeployLogger deployLogger,
  }) async {
    final builder = FlutterBuilder(
      projectPath: projectPath,
      logger: logger,
      deployLogger: deployLogger,
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
      extraArgs: envConfig.setup.extraArgsForPlatform(platform),
    );

    return await builder.build(buildOptions);
  }

  /// Find an existing build artifact when --skip-build is used
  String? _findExistingArtifact({
    required String platform,
    required String environment,
    required EnvironmentConfig envConfig,
    required BuildConfig buildConfig,
    required String basePath,
  }) {
    if (platform == 'android') {
      final buildFormat = buildConfig.platforms.android.buildFormat;
      final extension = buildFormat == 'aab' ? '.aab' : '.apk';

      // Check standard Flutter output path
      final outputDir = path.join(
        basePath, 'build', 'app', 'outputs',
        buildFormat == 'aab' ? 'bundle' : 'apk',
        environment, envConfig.setup.buildMode,
      );

      final dir = Directory(outputDir);
      if (dir.existsSync()) {
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith(extension))
            .toList();
        if (files.isNotEmpty) return files.first.path;
      }

      // Also check flutter-apk path (older Flutter versions)
      final altDir = path.join(
        basePath, 'build', 'app', 'outputs', 'flutter-apk',
      );
      final altDirObj = Directory(altDir);
      if (altDirObj.existsSync()) {
        final files = altDirObj
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.endsWith(extension) &&
                f.path.contains(environment))
            .toList();
        if (files.isNotEmpty) return files.first.path;
      }
    } else if (platform == 'ios') {
      final outputDir = path.join(basePath, 'build', 'ios', 'ipa');
      final dir = Directory(outputDir);
      if (dir.existsSync()) {
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.ipa'))
            .toList();
        if (files.isNotEmpty) return files.first.path;
      }
    }

    return null;
  }

  /// Upload to Firebase via REST API using service account credentials.
  Future<UploadResult> _uploadToFirebase({
    required String artifactPath,
    required String appId,
    String? releaseNotes,
    String? groups,
    required String projectNumber,
    required String? credentialsFile,
    required int timeout,
    required DeployLogger deployLogger,
  }) async {
    final basePath = projectPath ?? Directory.current.path;

    deployLogger.info('Authenticating with service account...');
    final auth = await FirebaseAuth.fromConfig(
      credentialsFile: credentialsFile,
      projectPath: basePath,
    );
    deployLogger.success('Authenticated');

    try {
      final uploader = FirebaseUploader(
        projectPath: projectPath,
        logger: logger,
        auth: auth,
      );

      // Auto-gitignore credentials file
      await uploader.addToGitignore('.firebase-credentials.json');

      final uploadOptions = UploadOptions(
        artifactPath: artifactPath,
        appId: appId,
        releaseNotes: releaseNotes,
        groups: groups,
        projectNumber: projectNumber,
        timeout: timeout,
      );

      deployLogger.progress('Uploading artifact...');
      final result = await uploader.upload(uploadOptions);

      if (result.success) {
        deployLogger.success('Artifact uploaded successfully');
        if (result.releaseName != null) {
          deployLogger.info('Release: ${result.releaseName}');
        }
      } else {
        deployLogger.error('Upload failed: ${result.error}');
      }

      return result;
    } finally {
      auth.close();
    }
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
