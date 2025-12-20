import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';

/// Flutter build configuration
class BuildOptions {
  final String environment; // flavor
  final String buildMode; // release or debug
  final String platform; // android or ios
  final String buildFormat; // apk, aab, or ipa
  final bool obfuscate;
  final bool clean;

  BuildOptions({
    required this.environment,
    required this.buildMode,
    required this.platform,
    required this.buildFormat,
    this.obfuscate = false,
    this.clean = true,
  });
}

/// Result of a Flutter build
class BuildResult {
  final bool success;
  final String? artifactPath;
  final String? error;
  final int? artifactSize; // in bytes
  final String? buildOutput; // Flutter build stdout/stderr

  BuildResult({
    required this.success,
    this.artifactPath,
    this.error,
    this.artifactSize,
    this.buildOutput,
  });

  String get artifactSizeFormatted {
    if (artifactSize == null) return 'Unknown';
    final sizeInMB = artifactSize! / (1024 * 1024);
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(2)} MB';
    } else {
      final sizeInKB = artifactSize! / 1024;
      return '${sizeInKB.toStringAsFixed(2)} KB';
    }
  }
}

/// Flutter builder for APK/IPA
class FlutterBuilder {
  final String? projectPath;
  final Logger logger;
  late final Shell _shell;

  FlutterBuilder({
    this.projectPath,
    Logger? logger,
  }) : logger = logger ?? Logger() {
    final basePath = projectPath ?? Directory.current.path;
    _shell = Shell(workingDirectory: basePath);
  }

  /// Build APK or IPA based on options
  Future<BuildResult> build(BuildOptions options) async {
    try {
      // Step 1: Clean if needed
      if (options.clean) {
        await _clean();
      }

      // Step 2: Get dependencies
      await _getDependencies();

      // Step 3: Build
      if (options.platform == 'android') {
        return await _buildAndroid(options);
      } else if (options.platform == 'ios') {
        return await _buildIos(options);
      } else {
        return BuildResult(
          success: false,
          error: 'Unsupported platform: ${options.platform}',
        );
      }
    } catch (e) {
      logger.err('Build failed: $e');
      return BuildResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Clean Flutter project
  Future<void> _clean() async {
    final progress = logger.progress('🧹 Cleaning project');
    try {
      await _shell.run('flutter clean');
      progress.complete('✅ Project cleaned');
    } catch (e) {
      progress.fail('❌ Clean failed');
      rethrow;
    }
  }

  /// Get Flutter dependencies
  Future<void> _getDependencies() async {
    final progress = logger.progress('📦 Getting dependencies');
    try {
      await _shell.run('flutter pub get');
      progress.complete('✅ Dependencies fetched');
    } catch (e) {
      progress.fail('❌ Failed to get dependencies');
      rethrow;
    }
  }

  /// Build Android APK or AAB
  Future<BuildResult> _buildAndroid(BuildOptions options) async {
    final basePath = projectPath ?? Directory.current.path;
    final buildType = options.buildFormat == 'aab' ? 'appbundle' : 'apk';
    final buildProgress = logger.progress(
      '🔨 Building ${buildType.toUpperCase()} for ${options.environment} (${options.buildMode})',
    );
    final outputBuffer = StringBuffer();

    try {
      // Prepare build command
      final buildArgs = <String>[
        'flutter',
        'build',
        buildType,
        '--flavor',
        options.environment,
        '--${options.buildMode}',
      ];

      // Add obfuscation flags for release builds
      if (options.buildMode == 'release' && options.obfuscate) {
        final symbolsDir = path.join(basePath, 'build', 'symbols', options.environment);
        await Directory(symbolsDir).create(recursive: true);

        buildArgs.addAll([
          '--obfuscate',
          '--split-debug-info=$symbolsDir',
        ]);

        logger.detail('🔒 Obfuscation enabled (symbols: $symbolsDir)');
      }

      // Run build and capture output
      final results = await _shell.run(buildArgs.join(' '));
      for (final result in results) {
        if (result.stdout.isNotEmpty) {
          outputBuffer.writeln('STDOUT:');
          outputBuffer.writeln(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          outputBuffer.writeln('STDERR:');
          outputBuffer.writeln(result.stderr);
        }
      }

      // Find built artifact
      final artifactPath = _findAndroidArtifact(
        basePath: basePath,
        environment: options.environment,
        buildMode: options.buildMode,
        buildFormat: options.buildFormat,
      );

      if (artifactPath == null) {
        buildProgress.fail('❌ Build artifact not found');
        return BuildResult(
          success: false,
          error: 'Build artifact not found',
          buildOutput: outputBuffer.toString(),
        );
      }

      final artifactFile = File(artifactPath);
      final artifactSize = await artifactFile.length();

      buildProgress.complete('✅ Build completed successfully');

      logger.info('📱 Artifact: ${path.basename(artifactPath)}');
      logger.info('📁 Location: $artifactPath');
      logger.info('📏 Size: ${_formatSize(artifactSize)}');

      return BuildResult(
        success: true,
        artifactPath: artifactPath,
        artifactSize: artifactSize,
        buildOutput: outputBuffer.toString(),
      );
    } catch (e) {
      buildProgress.fail('❌ Build failed');
      outputBuffer.writeln('ERROR:');
      outputBuffer.writeln(e.toString());
      return BuildResult(
        success: false,
        error: e.toString(),
        buildOutput: outputBuffer.toString(),
      );
    }
  }

  /// Build iOS IPA
  Future<BuildResult> _buildIos(BuildOptions options) async {
    final basePath = projectPath ?? Directory.current.path;
    final buildProgress = logger.progress(
      '🔨 Building IPA for ${options.environment} (${options.buildMode})',
    );
    final outputBuffer = StringBuffer();

    try {
      // Prepare build command
      final buildArgs = <String>[
        'flutter',
        'build',
        'ipa',
        '--flavor',
        options.environment,
        '--${options.buildMode}',
      ];

      // Add obfuscation flags for release builds
      if (options.buildMode == 'release' && options.obfuscate) {
        final symbolsDir = path.join(basePath, 'build', 'symbols', options.environment);
        await Directory(symbolsDir).create(recursive: true);

        buildArgs.addAll([
          '--obfuscate',
          '--split-debug-info=$symbolsDir',
        ]);

        logger.detail('🔒 Obfuscation enabled (symbols: $symbolsDir)');
      }

      // Run build and capture output
      final results = await _shell.run(buildArgs.join(' '));
      for (final result in results) {
        if (result.stdout.isNotEmpty) {
          outputBuffer.writeln('STDOUT:');
          outputBuffer.writeln(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          outputBuffer.writeln('STDERR:');
          outputBuffer.writeln(result.stderr);
        }
      }

      // Find built artifact
      final artifactPath = _findIosArtifact(
        basePath: basePath,
        environment: options.environment,
      );

      if (artifactPath == null) {
        buildProgress.fail('❌ Build artifact not found');
        return BuildResult(
          success: false,
          error: 'Build artifact not found',
          buildOutput: outputBuffer.toString(),
        );
      }

      final artifactFile = File(artifactPath);
      final artifactSize = await artifactFile.length();

      buildProgress.complete('✅ Build completed successfully');

      logger.info('📱 Artifact: ${path.basename(artifactPath)}');
      logger.info('📁 Location: $artifactPath');
      logger.info('📏 Size: ${_formatSize(artifactSize)}');

      return BuildResult(
        success: true,
        artifactPath: artifactPath,
        artifactSize: artifactSize,
        buildOutput: outputBuffer.toString(),
      );
    } catch (e) {
      buildProgress.fail('❌ Build failed');
      outputBuffer.writeln('ERROR:');
      outputBuffer.writeln(e.toString());
      return BuildResult(
        success: false,
        error: e.toString(),
        buildOutput: outputBuffer.toString(),
      );
    }
  }

  /// Find Android artifact (APK or AAB)
  String? _findAndroidArtifact({
    required String basePath,
    required String environment,
    required String buildMode,
    required String buildFormat,
  }) {
    final outputDir = path.join(
      basePath,
      'build',
      'app',
      'outputs',
      buildFormat,
      environment,
      buildMode,
    );

    final dir = Directory(outputDir);
    if (!dir.existsSync()) return null;

    final extension = buildFormat == 'aab' ? '.aab' : '.apk';
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(extension))
        .toList();

    return files.isNotEmpty ? files.first.path : null;
  }

  /// Find iOS artifact (IPA)
  String? _findIosArtifact({
    required String basePath,
    required String environment,
  }) {
    final outputDir = path.join(
      basePath,
      'build',
      'ios',
      'ipa',
    );

    final dir = Directory(outputDir);
    if (!dir.existsSync()) return null;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ipa'))
        .toList();

    return files.isNotEmpty ? files.first.path : null;
  }

  /// Format file size in human-readable format
  String _formatSize(int bytes) {
    final sizeInMB = bytes / (1024 * 1024);
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(2)} MB';
    } else {
      final sizeInKB = bytes / 1024;
      return '${sizeInKB.toStringAsFixed(2)} KB';
    }
  }

  /// Check if Flutter is installed
  Future<bool> isFlutterInstalled() async {
    try {
      await _shell.run('flutter --version');
      return true;
    } catch (e) {
      return false;
    }
  }
}
