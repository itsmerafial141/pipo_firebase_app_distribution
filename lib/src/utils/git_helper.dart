import 'dart:io';

import 'package:process_run/shell.dart';

/// Git operations helper
class GitHelper {
  final String? projectPath;
  late final Shell _shell;

  GitHelper({this.projectPath}) {
    final basePath = projectPath ?? Directory.current.path;
    _shell = Shell(workingDirectory: basePath);
  }

  /// Check if directory is a git repository
  Future<bool> isGitRepository() async {
    try {
      await _shell.run('git rev-parse --git-dir');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get current branch name
  Future<String?> getCurrentBranch() async {
    try {
      final result = await _shell.run('git rev-parse --abbrev-ref HEAD');
      return result.first.stdout.toString().trim();
    } catch (e) {
      return null;
    }
  }

  /// Get last tag for environment
  /// Example: appdist-dev-1.0.0+1
  Future<String?> getLastTag(String environment) async {
    try {
      final result = await _shell.run(
        'git describe --tags --match "appdist-$environment-*" --abbrev=0',
      );
      return result.first.stdout.toString().trim();
    } catch (e) {
      return null;
    }
  }

  /// Generate release notes since last tag
  Future<String> generateReleaseNotes({
    required String version,
    required String environment,
    required String buildMode,
  }) async {
    final lastTag = await getLastTag(environment);
    String changes;

    if (lastTag != null && lastTag.isNotEmpty) {
      try {
        final result = await _shell.run(
          'git log --pretty=format:"- %h %s" $lastTag..HEAD',
        );
        changes = result.first.stdout.toString().trim();
        if (changes.isEmpty) {
          changes = '- No code changes since last upload.';
        }
      } catch (e) {
        changes = '- Unable to retrieve changes.';
      }
    } else {
      try {
        final result = await _shell.run(
          'git log -n 20 --pretty=format:"- %h %s"',
        );
        changes = result.first.stdout.toString().trim();
      } catch (e) {
        changes = '- No git history available.';
      }
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return '''
🚀 App Build $version ($environment)

📱 Environment: $environment
🏗️  Build Mode: $buildMode
📅 Build Date: $dateStr
🔢 Version: $version

📝 Changes since last upload:
$changes
''';
  }

  /// Create git tag
  Future<bool> createTag({
    required String tagName,
    required String message,
  }) async {
    try {
      await _shell.run('git tag -a "$tagName" -m "$message"');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create or move latest tag for environment
  Future<bool> createLatestTag({
    required String environment,
    required String version,
  }) async {
    try {
      final tagName = 'appdist-$environment-latest';
      final message = 'Latest App Distribution $version ($environment)';

      await _shell.run('git tag -f -a "$tagName" -m "$message"');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Push tag to remote
  Future<bool> pushTag({
    required String tagName,
    bool force = false,
  }) async {
    try {
      final remote = await _getRemoteName();
      final forceFlag = force ? '-f' : '';
      await _shell.run('git push $forceFlag "$remote" "$tagName"');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Commit changes
  Future<bool> commit({
    required List<String> files,
    required String message,
  }) async {
    try {
      // Add files
      for (final file in files) {
        await _shell.run('git add "$file"');
      }

      // Check if there are changes to commit
      final statusResult = await _shell.run('git diff --cached --quiet -- ${files.join(" ")}');
      if (statusResult.first.exitCode == 0) {
        // No changes to commit
        return false;
      }

      // Commit
      await _shell.run('git commit -m "$message"');
      return true;
    } catch (e) {
      return true; // Changes exist, commit was made or error occurred
    }
  }

  /// Push commits to remote
  Future<bool> pushCommits() async {
    try {
      final remote = await _getRemoteName();
      final branch = await getCurrentBranch();

      if (branch == null || branch.isEmpty || branch == 'HEAD') {
        return false; // Detached HEAD
      }

      await _shell.run('git push "$remote" "$branch"');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get remote name (origin by default)
  Future<String> _getRemoteName() async {
    try {
      final result = await _shell.run('git remote');
      final remotes = result.first.stdout.toString().trim().split('\n');
      return remotes.isNotEmpty ? remotes.first : 'origin';
    } catch (e) {
      return 'origin';
    }
  }

  /// Get current commit hash
  Future<String?> getCurrentCommitHash() async {
    try {
      final result = await _shell.run('git rev-parse HEAD');
      return result.first.stdout.toString().trim();
    } catch (e) {
      return null;
    }
  }

  /// Check if there are uncommitted changes
  Future<bool> hasUncommittedChanges() async {
    try {
      final result = await _shell.run('git status --porcelain');
      final output = result.first.stdout.toString().trim();
      return output.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
