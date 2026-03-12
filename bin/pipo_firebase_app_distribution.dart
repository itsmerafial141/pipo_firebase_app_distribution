#!/usr/bin/env dart

import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:pipo_firebase_app_distribution/src/commands/deploy_command.dart';
import 'package:pipo_firebase_app_distribution/src/commands/init_command.dart';

const String version = '0.0.1';

void main(List<String> arguments) async {
  final parser = ArgParser(allowTrailingOptions: false)
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print the tool version.',
    );

  final logger = Logger();

  try {
    // Check for top-level flags only if the first argument is a flag
    if (arguments.isNotEmpty && arguments.first.startsWith('-')) {
      final results = parser.parse(arguments);

      if (results['help'] as bool) {
        _printUsage(parser);
        exit(0);
      }

      if (results['version'] as bool) {
        logger.info('pipo_firebase_app_distribution version $version');
        exit(0);
      }

      // If we get here, unknown flag
      logger.err('❌ Unknown option: ${arguments.first}');
      logger.info('');
      _printUsage(parser);
      exit(1);
    }

    // Get command from arguments directly (don't parse sub-command flags)
    if (arguments.isEmpty) {
      logger.err('❌ No command specified.');
      logger.info('');
      _printUsage(parser);
      exit(1);
    }

    final command = arguments.first;
    final commandArguments = arguments.skip(1).toList();

    // Execute command
    switch (command) {
      case 'init':
        final initCommand = InitCommand(logger: logger);
        final exitCode = await initCommand.run();
        exit(exitCode);

      case 'deploy':
        final exitCode = await _handleDeploy(logger, commandArguments);
        exit(exitCode);

      case 'help':
        _printUsage(parser);
        exit(0);

      default:
        logger.err('❌ Unknown command: $command');
        logger.info('');
        _printUsage(parser);
        exit(1);
    }
  } on FormatException catch (e) {
    logger.err('❌ ${e.message}');
    logger.info('');
    _printUsage(parser);
    exit(1);
  } catch (e) {
    logger.err('❌ An error occurred: $e');
    exit(1);
  }
}

Future<int> _handleDeploy(Logger logger, List<String> arguments) async {
  final deployParser = ArgParser()
    ..addOption(
      'platform',
      abbr: 'p',
      help: 'Platform to build (android, ios, or both)',
      allowed: ['android', 'ios', 'both'],
      defaultsTo: 'both',
    )
    ..addFlag(
      'skip-build',
      help: 'Skip building the app',
      negatable: false,
    )
    ..addFlag(
      'skip-upload',
      help: 'Skip uploading to Firebase',
      negatable: false,
    )
    ..addFlag(
      'skip-version-increment',
      help: 'Skip incrementing version number',
      negatable: false,
    )
    ..addFlag(
      'skip-git-tag',
      help: 'Skip creating git tags',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show help for deploy command',
      negatable: false,
    );

  try {
    final results = deployParser.parse(arguments);

    if (results['help'] as bool) {
      _printDeployHelp(deployParser);
      return 0;
    }

    // Get environment (required positional argument)
    if (results.rest.isEmpty) {
      logger.err('❌ Environment not specified.');
      logger.info('');
      _printDeployHelp(deployParser);
      return 1;
    }

    final environment = results.rest.first;

    final deployCommand = DeployCommand(logger: logger);
    final options = DeployCommandOptions(
      environment: environment,
      platform: results['platform'] as String?,
      skipBuild: results['skip-build'] as bool?,
      skipUpload: results['skip-upload'] as bool?,
      skipVersionIncrement: results['skip-version-increment'] as bool?,
      skipGitTag: results['skip-git-tag'] as bool?,
    );

    return await deployCommand.run(options);
  } on FormatException catch (e) {
    logger.err('❌ ${e.message}');
    logger.info('');
    _printDeployHelp(deployParser);
    return 1;
  }
}

void _printUsage(ArgParser parser) {
  print('''
╔══════════════════════════════════════════════════════════════╗
║        🚀 Pipo Firebase App Distribution CLI 🚀               ║
║     Auto-upload APK/IPA to Firebase App Distribution         ║
╚══════════════════════════════════════════════════════════════╝

A Dart CLI tool to automatically upload APK/IPA to Firebase App
Distribution with auto-detection of Firebase configuration.

Usage: pipo_firebase <command> [arguments]

Available commands:
  init        Initialize Firebase App Distribution configuration
              Scans google-services.json and GoogleService-Info.plist
              and generates build.yaml template

  deploy      Build and deploy app to Firebase App Distribution
              Reads configuration from build.yaml

Global options:
${parser.usage}

Examples:
  # Initialize configuration (generates build.yaml)
  pipo_firebase init

  # Deploy dev environment
  pipo_firebase deploy dev

  # Deploy staging for Android only
  pipo_firebase deploy staging --platform android

  # Deploy production with custom options
  pipo_firebase deploy production --skip-version-increment

  # Show help for deploy command
  pipo_firebase deploy --help

  # Show help
  pipo_firebase --help

  # Show version
  pipo_firebase --version

For more information, visit:
https://pub.dev/packages/pipo_firebase_app_distribution
''');
}

void _printDeployHelp(ArgParser parser) {
  print('''
╔══════════════════════════════════════════════════════════════╗
║                   Deploy Command Help                        ║
╚══════════════════════════════════════════════════════════════╝

Build and deploy app to Firebase App Distribution.

Usage: pipo_firebase deploy <environment> [options]

Arguments:
  <environment>    Environment to deploy (dev, staging, production, etc.)
                   Must match an environment defined in build.yaml

Options:
${parser.usage}

What this command does:
  1. ✅ Read build configuration from build.yaml
  2. 📊 Auto-increment version number (if configured)
  3. 🔨 Build APK/IPA for specified platform(s)
  4. 📝 Generate release notes from git commits
  5. ☁️  Upload to Firebase App Distribution
  6. 🏷️  Create git tags and commit changes

Examples:
  # Deploy dev environment (both platforms)
  pipo_firebase deploy dev

  # Deploy staging for Android only
  pipo_firebase deploy staging --platform android

  # Deploy production for iOS only
  pipo_firebase deploy production --platform ios

  # Build only, don't upload
  pipo_firebase deploy dev --skip-upload

  # Upload existing build without rebuilding
  pipo_firebase deploy dev --skip-build

  # Deploy without incrementing version
  pipo_firebase deploy staging --skip-version-increment

  # Deploy without git operations
  pipo_firebase deploy production --skip-git-tag

Configuration:
  All settings are read from build.yaml in your project root.
  Run "pipo_firebase init" to generate build.yaml.

Requirements:
  - Flutter SDK installed
  - build.yaml exists in project root
  - Service account credentials (for upload):
    .firebase-credentials.json in project root, or
    credentials_file in build.yaml, or
    GOOGLE_APPLICATION_CREDENTIALS env var

For more information, visit:
https://pub.dev/packages/pipo_firebase_app_distribution
''');
}
