import 'dart:io';

import 'package:path/path.dart' as path;

/// Real-time deployment logger that streams all commands and output to a log file.
///
/// Users can monitor progress with `tail -f .pipo_logs/deploy_YYYYMMDD_HHMMSS.log`
class DeployLogger {
  final String? projectPath;
  File? _logFile;
  String? _logPath;
  final Stopwatch _stopwatch = Stopwatch();

  DeployLogger({this.projectPath});

  /// Get logs directory
  String _getLogsDir() {
    final basePath = projectPath ?? Directory.current.path;
    return path.join(basePath, '.pipo_logs');
  }

  /// Get current log file path (null if not started)
  String? get logPath => _logPath;

  /// Get relative path for display
  String get relativeLogPath {
    if (_logPath == null) return '';
    final basePath = projectPath ?? Directory.current.path;
    return path.relative(_logPath!, from: basePath);
  }

  /// Start a new deployment log session
  Future<String> start({
    required String environment,
    String? platform,
  }) async {
    final logsDir = Directory(_getLogsDir());
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
      await _addToGitignore('.pipo_logs/');
    }

    // Clean old logs before starting new one
    await cleanOldLogs();

    final filename = _generateFilename();
    _logPath = path.join(_getLogsDir(), filename);
    _logFile = File(_logPath!);

    // Create the file
    _logFile!.writeAsStringSync('');
    _stopwatch.start();

    _writeLine('╔══════════════════════════════════════════════════════════════╗');
    _writeLine('║        🚀 Pipo Firebase App Distribution Deploy 🚀            ║');
    _writeLine('║                  Deployment Log                              ║');
    _writeLine('╚══════════════════════════════════════════════════════════════╝');
    _writeLine('');
    _writeLine('Started at: ${DateTime.now()}');
    _writeLine('Environment: $environment');
    if (platform != null) {
      _writeLine('Platform: $platform');
    }
    _writeLine('');
    _writeLine('Tip: Monitor this log in real-time with:');
    _writeLine('  tail -f $relativeLogPath');
    _writeLine('');
    _separator();

    return _logPath!;
  }

  /// Log a step header (e.g. "READING CONFIGURATION", "BUILD ANDROID")
  void step(String title) {
    _writeLine('');
    _separator();
    _writeLine('  [$_elapsed] $title');
    _separator();
    _writeLine('');
  }

  /// Log an info message
  void info(String message) {
    _writeLine('[$_elapsed] $message');
  }

  /// Log a success message
  void success(String message) {
    _writeLine('[$_elapsed] ✅ $message');
  }

  /// Log a warning message
  void warn(String message) {
    _writeLine('[$_elapsed] ⚠️  $message');
  }

  /// Log an error message
  void error(String message) {
    _writeLine('[$_elapsed] ❌ $message');
  }

  /// Log a command that is about to be executed
  void command(String cmd) {
    _writeLine('[$_elapsed] \$ $cmd');
  }

  /// Log command stdout output (line by line, real-time)
  void stdout(String line) {
    _writeLine('  │ $line');
  }

  /// Log command stderr output (line by line, real-time)
  void stderr(String line) {
    _writeLine('  │ [stderr] $line');
  }

  /// Log a sub-step progress update
  void progress(String message) {
    _writeLine('[$_elapsed] ⏳ $message');
  }

  /// Log detailed error information (build error, upload error, etc.)
  void errorDetail({
    required String title,
    required String errorMessage,
    String? stackTrace,
    String? output,
    List<String>? troubleshootingTips,
  }) {
    _writeLine('');
    _writeLine('╔══════════════════════════════════════════════════════════════╗');
    _writeLine('║  ❌ $title');
    _writeLine('╚══════════════════════════════════════════════════════════════╝');
    _writeLine('');
    _writeLine('Error: $errorMessage');

    if (stackTrace != null && stackTrace.isNotEmpty) {
      _writeLine('');
      _writeLine('Stack Trace:');
      _writeLine(stackTrace);
    }

    if (output != null && output.isNotEmpty) {
      _writeLine('');
      _writeLine('Output:');
      _writeLine(output);
    }

    if (troubleshootingTips != null && troubleshootingTips.isNotEmpty) {
      _writeLine('');
      _writeLine('Troubleshooting:');
      for (var i = 0; i < troubleshootingTips.length; i++) {
        _writeLine('  ${i + 1}. ${troubleshootingTips[i]}');
      }
    }
    _writeLine('');
  }

  /// Log deployment completion summary
  void complete({
    required bool success,
    String? environment,
    String? version,
    List<String>? platforms,
    bool? uploaded,
  }) {
    _writeLine('');
    _separator();
    if (success) {
      _writeLine('  🎉 DEPLOYMENT COMPLETE');
    } else {
      _writeLine('  ❌ DEPLOYMENT FAILED');
    }
    _separator();
    _writeLine('');
    _writeLine('Finished at: ${DateTime.now()}');
    _writeLine('Duration: $_elapsed');
    if (environment != null) _writeLine('Environment: $environment');
    if (version != null) _writeLine('Version: $version');
    if (platforms != null) _writeLine('Platforms: ${platforms.join(", ")}');
    if (uploaded != null) _writeLine('Uploaded: ${uploaded ? "Yes" : "No"}');
    _writeLine('');
  }

  /// Close the log file (no-op since we use sync writes, kept for API compat)
  Future<void> close() async {
    _stopwatch.stop();
    _logFile = null;
  }

  /// Get elapsed time formatted as MM:SS
  String get _elapsed {
    final duration = _stopwatch.elapsed;
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Write a line to the log file synchronously for real-time reading.
  ///
  /// Uses [writeAsStringSync] in append mode — each call immediately
  /// flushes to disk so `tail -f` picks it up instantly.
  void _writeLine(String line) {
    _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  /// Write a separator line
  void _separator() {
    _writeLine('═══════════════════════════════════════════════════════════════');
  }

  /// Generate log filename with timestamp
  String _generateFilename() {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'deploy_$timestamp.log';
  }

  /// Clean old logs (keep last 10)
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

      logFiles.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      final toDelete = logFiles.length - keepLast;
      for (var i = 0; i < toDelete; i++) {
        await logFiles[i].delete();
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Add entry to .gitignore if not already present
  Future<void> _addToGitignore(String entry) async {
    try {
      final basePath = projectPath ?? Directory.current.path;
      final gitignoreFile = File(path.join(basePath, '.gitignore'));

      String content = '';
      if (await gitignoreFile.exists()) {
        content = await gitignoreFile.readAsString();
      }

      final lines = content.split('\n');
      if (lines.any((line) => line.trim() == entry)) {
        return;
      }

      if (content.isNotEmpty && !content.endsWith('\n')) {
        content += '\n';
      }
      content += '# Pipo Firebase deployment logs (auto-generated)\n';
      content += '$entry\n';

      await gitignoreFile.writeAsString(content);
    } catch (e) {
      // Silently ignore gitignore errors
    }
  }
}
