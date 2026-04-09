import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../utils/deploy_logger.dart';

/// Flutter build configuration
class BuildOptions {
  final String environment; // flavor
  final String buildMode; // release or debug
  final String platform; // android or ios
  final String buildFormat; // apk, aab, or ipa
  final bool obfuscate;
  final bool clean;
  final List<String> extraArgs;

  BuildOptions({
    required this.environment,
    required this.buildMode,
    required this.platform,
    required this.buildFormat,
    this.obfuscate = false,
    this.clean = true,
    this.extraArgs = const [],
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
  final DeployLogger? deployLogger;
  final bool useFvm;

  FlutterBuilder({
    this.projectPath,
    Logger? logger,
    this.deployLogger,
    this.useFvm = false,
  }) : logger = logger ?? Logger();

  String get _basePath => projectPath ?? Directory.current.path;

  /// Returns the flutter command prefix (with or without fvm)
  String get _flutter => useFvm ? 'fvm flutter' : 'flutter';

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
      deployLogger?.error('Build failed: $e');
      return BuildResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Run a command with real-time streaming to DeployLogger
  Future<_ProcessResult> _runStreaming(String command) async {
    deployLogger?.command(command);

    final parts = command.split(' ');
    final process = await Process.start(
      parts.first,
      parts.skip(1).toList(),
      workingDirectory: _basePath,
      runInShell: true,
    );

    final outputBuffer = StringBuffer();

    // Stream stdout line by line
    final stdoutFuture = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      outputBuffer.writeln(line);
      deployLogger?.stdout(line);
    }).asFuture();

    // Stream stderr line by line
    final stderrFuture = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      outputBuffer.writeln(line);
      deployLogger?.stderr(line);
    }).asFuture();

    // Wait for streams to complete
    await Future.wait([stdoutFuture, stderrFuture]);
    final exitCode = await process.exitCode;

    return _ProcessResult(
      exitCode: exitCode,
      output: outputBuffer.toString(),
    );
  }

  /// Clean Flutter project
  Future<void> _clean() async {
    final progress = logger.progress('🧹 Cleaning project');
    deployLogger?.progress('Cleaning project...');

    try {
      final result = await _runStreaming('$_flutter clean');
      if (result.exitCode != 0) {
        progress.fail('❌ Clean failed');
        deployLogger?.error('Clean failed (exit code: ${result.exitCode})');
        throw ProcessException('flutter', ['clean'], 'Clean failed', result.exitCode);
      }
      progress.complete('✅ Project cleaned');
      deployLogger?.success('Project cleaned');
    } catch (e) {
      progress.fail('❌ Clean failed');
      deployLogger?.error('Clean failed: $e');
      rethrow;
    }
  }

  /// Get Flutter dependencies
  Future<void> _getDependencies() async {
    final progress = logger.progress('📦 Getting dependencies');
    deployLogger?.progress('Getting dependencies...');

    try {
      final result = await _runStreaming('$_flutter pub get');
      if (result.exitCode != 0) {
        progress.fail('❌ Failed to get dependencies');
        deployLogger?.error('Failed to get dependencies (exit code: ${result.exitCode})');
        throw ProcessException('flutter', ['pub', 'get'], 'pub get failed', result.exitCode);
      }
      progress.complete('✅ Dependencies fetched');
      deployLogger?.success('Dependencies fetched');
    } catch (e) {
      progress.fail('❌ Failed to get dependencies');
      deployLogger?.error('Failed to get dependencies: $e');
      rethrow;
    }
  }

  /// Build Android APK or AAB
  Future<BuildResult> _buildAndroid(BuildOptions options) async {
    final buildType = options.buildFormat == 'aab' ? 'appbundle' : 'apk';
    final buildProgress = logger.progress(
      '🔨 Building ${buildType.toUpperCase()} for ${options.environment} (${options.buildMode})',
    );
    deployLogger?.progress(
      'Building ${buildType.toUpperCase()} for ${options.environment} (${options.buildMode})...',
    );

    try {
      // Prepare build command
      final buildArgs = <String>[
        ...(_flutter.split(' ')),
        'build',
        buildType,
        '--flavor',
        options.environment,
        '--${options.buildMode}',
      ];

      // Add obfuscation flags for release builds
      if (options.buildMode == 'release' && options.obfuscate) {
        final symbolsDir = path.join(_basePath, 'build', 'symbols', options.environment);
        await Directory(symbolsDir).create(recursive: true);

        buildArgs.addAll([
          '--obfuscate',
          '--split-debug-info=$symbolsDir',
        ]);

        logger.detail('🔒 Obfuscation enabled (symbols: $symbolsDir)');
        deployLogger?.info('Obfuscation enabled (symbols: $symbolsDir)');
      }

      // Add custom extra args
      if (options.extraArgs.isNotEmpty) {
        buildArgs.addAll(options.extraArgs);
        logger.detail('📎 Extra args: ${options.extraArgs.join(" ")}');
        deployLogger?.info('Extra args: ${options.extraArgs.join(" ")}');
      }

      // Run build with real-time streaming
      final result = await _runStreaming(buildArgs.join(' '));

      if (result.exitCode != 0) {
        buildProgress.fail('❌ Build failed');
        deployLogger?.error('Build failed (exit code: ${result.exitCode})');
        return BuildResult(
          success: false,
          error: 'Build failed with exit code ${result.exitCode}',
          buildOutput: result.output,
        );
      }

      // Find built artifact
      final artifactPath = _findAndroidArtifact(
        basePath: _basePath,
        environment: options.environment,
        buildMode: options.buildMode,
        buildFormat: options.buildFormat,
      );

      if (artifactPath == null) {
        buildProgress.fail('❌ Build artifact not found');
        deployLogger?.error('Build artifact not found');
        return BuildResult(
          success: false,
          error: 'Build artifact not found',
          buildOutput: result.output,
        );
      }

      final artifactFile = File(artifactPath);
      final artifactSize = await artifactFile.length();

      buildProgress.complete('✅ Build completed successfully');

      logger.info('📱 Artifact: ${path.basename(artifactPath)}');
      logger.info('📁 Location: $artifactPath');
      logger.info('📏 Size: ${_formatSize(artifactSize)}');

      deployLogger?.success('Build completed successfully');
      deployLogger?.info('Artifact: ${path.basename(artifactPath)}');
      deployLogger?.info('Location: $artifactPath');
      deployLogger?.info('Size: ${_formatSize(artifactSize)}');

      return BuildResult(
        success: true,
        artifactPath: artifactPath,
        artifactSize: artifactSize,
        buildOutput: result.output,
      );
    } catch (e) {
      buildProgress.fail('❌ Build failed');
      deployLogger?.error('Build crashed: $e');
      return BuildResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Build iOS IPA
  Future<BuildResult> _buildIos(BuildOptions options) async {
    final buildProgress = logger.progress(
      '🔨 Building IPA for ${options.environment} (${options.buildMode})',
    );
    deployLogger?.progress(
      'Building IPA for ${options.environment} (${options.buildMode})...',
    );

    try {
      // Prepare build command
      final buildArgs = <String>[
        ...(_flutter.split(' ')),
        'build',
        'ipa',
        '--flavor',
        options.environment,
        '--${options.buildMode}',
      ];

      // Add obfuscation flags for release builds
      if (options.buildMode == 'release' && options.obfuscate) {
        final symbolsDir = path.join(_basePath, 'build', 'symbols', options.environment);
        await Directory(symbolsDir).create(recursive: true);

        buildArgs.addAll([
          '--obfuscate',
          '--split-debug-info=$symbolsDir',
        ]);

        logger.detail('🔒 Obfuscation enabled (symbols: $symbolsDir)');
        deployLogger?.info('Obfuscation enabled (symbols: $symbolsDir)');
      }

      // Add custom extra args
      if (options.extraArgs.isNotEmpty) {
        buildArgs.addAll(options.extraArgs);
        logger.detail('📎 Extra args: ${options.extraArgs.join(" ")}');
        deployLogger?.info('Extra args: ${options.extraArgs.join(" ")}');
      }

      // Run build with real-time streaming
      final result = await _runStreaming(buildArgs.join(' '));

      if (result.exitCode != 0) {
        buildProgress.fail('❌ Build failed');
        deployLogger?.error('Build failed (exit code: ${result.exitCode})');
        return BuildResult(
          success: false,
          error: 'Build failed with exit code ${result.exitCode}',
          buildOutput: result.output,
        );
      }

      // Find built artifact
      final artifactPath = _findIosArtifact(
        basePath: _basePath,
        environment: options.environment,
      );

      if (artifactPath == null) {
        buildProgress.fail('❌ Build artifact not found');
        deployLogger?.error('Build artifact not found');
        return BuildResult(
          success: false,
          error: 'Build artifact not found',
          buildOutput: result.output,
        );
      }

      final artifactFile = File(artifactPath);
      final artifactSize = await artifactFile.length();

      buildProgress.complete('✅ Build completed successfully');

      logger.info('📱 Artifact: ${path.basename(artifactPath)}');
      logger.info('📁 Location: $artifactPath');
      logger.info('📏 Size: ${_formatSize(artifactSize)}');

      deployLogger?.success('Build completed successfully');
      deployLogger?.info('Artifact: ${path.basename(artifactPath)}');
      deployLogger?.info('Location: $artifactPath');
      deployLogger?.info('Size: ${_formatSize(artifactSize)}');

      return BuildResult(
        success: true,
        artifactPath: artifactPath,
        artifactSize: artifactSize,
        buildOutput: result.output,
      );
    } catch (e) {
      buildProgress.fail('❌ Build failed');
      deployLogger?.error('Build crashed: $e');
      return BuildResult(
        success: false,
        error: e.toString(),
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
    final extension = buildFormat == 'aab' ? '.aab' : '.apk';
    final capitalizedMode =
        buildMode[0].toUpperCase() + buildMode.substring(1);

    final candidateDirs = <String>[
      if (buildFormat == 'aab') ...[
        // AAB output: build/app/outputs/bundle/{flavor}Release/
        path.join(basePath, 'build', 'app', 'outputs', 'bundle',
            '$environment$capitalizedMode'),
      ] else ...[
        // APK output (modern): build/app/outputs/flutter-apk/
        path.join(basePath, 'build', 'app', 'outputs', 'flutter-apk'),
        // APK output (legacy): build/app/outputs/apk/{flavor}/release/
        path.join(
            basePath, 'build', 'app', 'outputs', 'apk', environment, buildMode),
      ],
    ];

    for (final outputDir in candidateDirs) {
      final dir = Directory(outputDir);
      if (!dir.existsSync()) continue;

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith(extension) && f.path.contains(environment))
          .toList();

      if (files.isNotEmpty) return files.first.path;
    }

    return null;
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
      final cmd = _flutter.split(' ');
      final result = await Process.run(cmd.first, [...cmd.skip(1), '--version'],
          workingDirectory: _basePath, runInShell: true);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
}

/// Internal process result holder
class _ProcessResult {
  final int exitCode;
  final String output;

  _ProcessResult({required this.exitCode, required this.output});
}
