import 'dart:io';

import 'package:path/path.dart' as path;

/// Error logger for build and upload failures
class ErrorLogger {
  final String? projectPath;

  ErrorLogger({this.projectPath});

  /// Get logs directory
  String _getLogsDir() {
    final basePath = projectPath ?? Directory.current.path;
    return path.join(basePath, '.pipo_logs');
  }

  /// Ensure logs directory exists
  Future<void> _ensureLogsDir() async {
    final logsDir = Directory(_getLogsDir());
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
      // Add to .gitignore when first created
      await _addToGitignore('.pipo_logs/');
    }
  }

  /// Add file/folder to .gitignore if not already present
  Future<void> _addToGitignore(String entry) async {
    try {
      final basePath = projectPath ?? Directory.current.path;
      final gitignoreFile = File(path.join(basePath, '.gitignore'));

      // Read existing .gitignore or create new one
      String content = '';
      if (await gitignoreFile.exists()) {
        content = await gitignoreFile.readAsString();
      }

      // Check if already in .gitignore
      final lines = content.split('\n');
      if (lines.any((line) => line.trim() == entry)) {
        return; // Already exists
      }

      // Add to .gitignore
      if (content.isNotEmpty && !content.endsWith('\n')) {
        content += '\n';
      }
      content += '# Pipo Firebase error logs (auto-generated)\n';
      content += '$entry\n';

      await gitignoreFile.writeAsString(content);
    } catch (e) {
      // Silently ignore gitignore errors
    }
  }

  /// Generate log filename with timestamp
  String _generateLogFilename(String type) {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '${type}_$timestamp.log';
  }

  /// Log build error
  Future<String> logBuildError({
    required String platform,
    required String environment,
    required String buildMode,
    required String error,
    String? stackTrace,
    String? buildOutput,
  }) async {
    await _ensureLogsDir();

    final filename = _generateLogFilename('build_error');
    final logPath = path.join(_getLogsDir(), filename);
    final logFile = File(logPath);

    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                    BUILD ERROR LOG                           ║');
    buffer.writeln('╚══════════════════════════════════════════════════════════════╝');
    buffer.writeln();
    buffer.writeln('Timestamp: ${DateTime.now()}');
    buffer.writeln('Platform: $platform');
    buffer.writeln('Environment: $environment');
    buffer.writeln('Build Mode: $buildMode');
    buffer.writeln();
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('ERROR MESSAGE');
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln(error);
    buffer.writeln();

    if (stackTrace != null && stackTrace.isNotEmpty) {
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln('STACK TRACE');
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln(stackTrace);
      buffer.writeln();
    }

    if (buildOutput != null && buildOutput.isNotEmpty) {
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln('BUILD OUTPUT');
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln(buildOutput);
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('TROUBLESHOOTING TIPS');
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('1. Check Flutter SDK installation: flutter doctor');
    buffer.writeln('2. Verify flavor configuration in android/app/build.gradle');
    buffer.writeln('3. Clean and rebuild: flutter clean && flutter pub get');
    buffer.writeln('4. Check for missing dependencies in pubspec.yaml');
    buffer.writeln('5. Verify Firebase configuration files are present');
    buffer.writeln();

    await logFile.writeAsString(buffer.toString());

    return logPath;
  }

  /// Log upload error
  Future<String> logUploadError({
    required String platform,
    required String environment,
    required String appId,
    required String artifactPath,
    required String error,
    String? stackTrace,
    String? firebaseOutput,
  }) async {
    await _ensureLogsDir();

    final filename = _generateLogFilename('upload_error');
    final logPath = path.join(_getLogsDir(), filename);
    final logFile = File(logPath);

    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                   UPLOAD ERROR LOG                           ║');
    buffer.writeln('╚══════════════════════════════════════════════════════════════╝');
    buffer.writeln();
    buffer.writeln('Timestamp: ${DateTime.now()}');
    buffer.writeln('Platform: $platform');
    buffer.writeln('Environment: $environment');
    buffer.writeln('App ID: $appId');
    buffer.writeln('Artifact: $artifactPath');
    buffer.writeln();
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('ERROR MESSAGE');
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln(error);
    buffer.writeln();

    if (stackTrace != null && stackTrace.isNotEmpty) {
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln('STACK TRACE');
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln(stackTrace);
      buffer.writeln();
    }

    if (firebaseOutput != null && firebaseOutput.isNotEmpty) {
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln('FIREBASE CLI OUTPUT');
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln(firebaseOutput);
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('TROUBLESHOOTING TIPS');
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('1. Check Firebase CLI installation: firebase --version');
    buffer.writeln('2. Verify authentication: firebase login');
    buffer.writeln('3. Check Firebase token: echo \$FIREBASE_TOKEN');
    buffer.writeln('4. Verify App ID exists in Firebase Console');
    buffer.writeln('5. Check network connection and firewall settings');
    buffer.writeln('6. Try increasing timeout in build.yaml');
    buffer.writeln();

    await logFile.writeAsString(buffer.toString());

    return logPath;
  }

  /// Log general deployment error
  Future<String> logDeploymentError({
    required String environment,
    required String error,
    String? stackTrace,
  }) async {
    await _ensureLogsDir();

    final filename = _generateLogFilename('deployment_error');
    final logPath = path.join(_getLogsDir(), filename);
    final logFile = File(logPath);

    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                 DEPLOYMENT ERROR LOG                         ║');
    buffer.writeln('╚══════════════════════════════════════════════════════════════╝');
    buffer.writeln();
    buffer.writeln('Timestamp: ${DateTime.now()}');
    buffer.writeln('Environment: $environment');
    buffer.writeln();
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('ERROR MESSAGE');
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln(error);
    buffer.writeln();

    if (stackTrace != null && stackTrace.isNotEmpty) {
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln('STACK TRACE');
      buffer.writeln('═══════════════════════════════════════════════════════════════');
      buffer.writeln(stackTrace);
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('TROUBLESHOOTING TIPS');
    buffer.writeln('═══════════════════════════════════════════════════════════════');
    buffer.writeln('1. Verify build.yaml configuration');
    buffer.writeln('2. Check all required tools are installed (Flutter, Firebase CLI)');
    buffer.writeln('3. Run: pipo_firebase init to regenerate configuration');
    buffer.writeln('4. Check project directory permissions');
    buffer.writeln();

    await logFile.writeAsString(buffer.toString());

    return logPath;
  }

  /// Clean old logs (keep last 10 logs)
  Future<void> cleanOldLogs({int keepLast = 10}) async {
    try {
      final logsDir = Directory(_getLogsDir());
      if (!await logsDir.exists()) return;

      final logFiles = await logsDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      if (logFiles.length <= keepLast) return;

      // Sort by modification time (oldest first)
      logFiles.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      // Delete oldest logs
      final toDelete = logFiles.length - keepLast;
      for (var i = 0; i < toDelete; i++) {
        await logFiles[i].delete();
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Get relative path for log file
  String getRelativePath(String logPath) {
    final basePath = projectPath ?? Directory.current.path;
    return path.relative(logPath, from: basePath);
  }
}
