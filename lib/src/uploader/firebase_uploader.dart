import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';

/// Firebase upload configuration
class UploadOptions {
  final String artifactPath;
  final String appId;
  final String? releaseNotes;
  final String? releaseNotesFile;
  final String? groups;
  final String? testers;
  final String projectId;
  final String? token; // CI token
  final int timeout;

  UploadOptions({
    required this.artifactPath,
    required this.appId,
    this.releaseNotes,
    this.releaseNotesFile,
    this.groups,
    this.testers,
    required this.projectId,
    this.token,
    this.timeout = 600, // 10 minutes default
  });
}

/// Result of Firebase upload
class UploadResult {
  final bool success;
  final String? error;
  final String? downloadUrl;
  final String? firebaseOutput; // Firebase CLI stdout/stderr

  UploadResult({
    required this.success,
    this.error,
    this.downloadUrl,
    this.firebaseOutput,
  });
}

/// Firebase App Distribution uploader
class FirebaseUploader {
  final String? projectPath;
  final Logger logger;
  late final Shell _shell;

  FirebaseUploader({
    this.projectPath,
    Logger? logger,
  }) : logger = logger ?? Logger() {
    final basePath = projectPath ?? Directory.current.path;
    _shell = Shell(workingDirectory: basePath);
  }

  /// Upload artifact to Firebase App Distribution
  Future<UploadResult> upload(UploadOptions options) async {
    try {
      // Check Firebase CLI installation
      logger.detail('🔍 Checking Firebase CLI installation...');
      if (!await isFirebaseInstalled()) {
        logger.err('❌ Firebase CLI not found!');
        return UploadResult(
          success: false,
          error: 'Firebase CLI is not installed.\n'
              'Install it with: npm install -g firebase-tools\n'
              'Or visit: https://firebase.google.com/docs/cli',
        );
      }
      logger.detail('✅ Firebase CLI found');

      // Ensure Firebase authentication
      logger.detail('🔍 Verifying Firebase authentication...');
      final validToken = await ensureAuthentication(
        options.projectId,
        options.token,
      );

      if (validToken == null && options.token == null) {
        // Check if authentication succeeded without token (interactive login)
        final hasAccess = await checkProjectAccess(options.projectId);
        if (!hasAccess) {
          logger.err('');
          logger.err('❌ Authentication failed or project not accessible');
          return UploadResult(
            success: false,
            error: 'Firebase authentication failed. Please ensure you have access to project: ${options.projectId}',
          );
        }
      }

      // Use the valid token for upload
      final uploadToken = validToken ?? options.token;

      // Verify artifact exists
      logger.detail('🔍 Verifying artifact file...');
      final artifactFile = File(options.artifactPath);
      if (!await artifactFile.exists()) {
        logger.err('❌ Artifact file not found: ${options.artifactPath}');
        return UploadResult(
          success: false,
          error: 'Artifact file not found: ${options.artifactPath}',
        );
      }
      final artifactSize = await artifactFile.length();
      logger.detail('✅ Artifact found (${_formatSize(artifactSize)})');

      // Set Firebase project
      logger.detail('🔍 Setting Firebase project: ${options.projectId}');
      await _setFirebaseProject(options.projectId, uploadToken);

      // Prepare release notes
      String? releaseNotesFile = options.releaseNotesFile;
      if (releaseNotesFile == null && options.releaseNotes != null) {
        logger.detail('📝 Creating release notes file...');
        releaseNotesFile = await _createTempReleaseNotesFile(options.releaseNotes!);
      }

      // Upload to Firebase App Distribution
      logger.info('📤 Starting upload to Firebase App Distribution...');
      logger.info('   App ID: ${options.appId}');
      if (options.groups != null) {
        logger.info('   Groups: ${options.groups}');
      }
      logger.info('');

      final uploadProgress = logger.progress('⏳ Uploading artifact');

      try {
        final result = await _uploadToFirebase(
          artifactPath: options.artifactPath,
          appId: options.appId,
          releaseNotesFile: releaseNotesFile,
          groups: options.groups,
          testers: options.testers,
          token: uploadToken,
          timeout: options.timeout,
        );

        if (result.success) {
          uploadProgress.complete('✅ Upload completed successfully');

          logger.info('');
          logger.success('🎉 App successfully distributed to Firebase!');
          logger.info('');
          logger.info('📱 App ID: ${options.appId}');
          if (options.groups != null) {
            logger.info('👥 Groups: ${options.groups}');
          }
          logger.info('');
          logger.info('🔗 Check Firebase Console for distribution link');

          return UploadResult(
            success: true,
            firebaseOutput: result.output,
          );
        } else {
          uploadProgress.fail('❌ Upload failed');
          return UploadResult(
            success: false,
            error: 'Upload to Firebase failed. Check upload logs for details.',
            firebaseOutput: result.output,
          );
        }
      } finally {
        // Clean up temp release notes file
        if (releaseNotesFile != null &&
            releaseNotesFile != options.releaseNotesFile) {
          try {
            await File(releaseNotesFile).delete();
          } catch (e) {
            // Ignore cleanup errors
          }
        }
      }
    } on TimeoutException catch (e) {
      logger.err('⏱️  Upload timeout: $e');
      return UploadResult(
        success: false,
        error: 'Upload timed out after ${options.timeout} seconds.\n'
            'Try increasing timeout in build.yaml or check your network connection.',
      );
    } catch (e, stackTrace) {
      logger.err('💥 Upload crashed: $e');
      logger.detail('Stack trace: $stackTrace');
      return UploadResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Format file size
  String _formatSize(int bytes) {
    final sizeInMB = bytes / (1024 * 1024);
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(2)} MB';
    } else {
      final sizeInKB = bytes / 1024;
      return '${sizeInKB.toStringAsFixed(2)} KB';
    }
  }

  /// Check if Firebase CLI is installed
  Future<bool> isFirebaseInstalled() async {
    try {
      await _shell.run('firebase --version');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Set Firebase project
  Future<void> _setFirebaseProject(String projectId, String? token) async {
    try {
      final command = token != null
          ? 'firebase use $projectId --token "$token"'
          : 'firebase use $projectId';

      await _shell.run(command);
      logger.detail('✅ Firebase project set to: $projectId');
    } catch (e) {
      logger.warn('⚠️  Failed to set Firebase project: $e');
      // Continue anyway, might work if project is already set
    }
  }

  /// Create temporary release notes file
  Future<String> _createTempReleaseNotesFile(String releaseNotes) async {
    final basePath = projectPath ?? Directory.current.path;
    final tempFile = File(path.join(basePath, '.firebase_release_notes.tmp'));
    await tempFile.writeAsString(releaseNotes);
    return tempFile.path;
  }

  /// Upload to Firebase App Distribution
  Future<({bool success, String? output})> _uploadToFirebase({
    required String artifactPath,
    required String appId,
    String? releaseNotesFile,
    String? groups,
    String? testers,
    String? token,
    required int timeout,
  }) async {
    final outputBuffer = StringBuffer();

    try {
      // Build Firebase command
      final commandParts = <String>[
        'firebase',
        'appdistribution:distribute',
        '"$artifactPath"',
        '--app',
        '"$appId"',
      ];

      if (releaseNotesFile != null) {
        commandParts.addAll(['--release-notes-file', '"$releaseNotesFile"']);
      }

      if (groups != null && groups.isNotEmpty) {
        commandParts.addAll(['--groups', '"$groups"']);
      }

      if (testers != null && testers.isNotEmpty) {
        commandParts.addAll(['--testers', '"$testers"']);
      }

      if (token != null) {
        commandParts.addAll(['--token', '"$token"']);
      }

      final command = commandParts.join(' ');

      logger.detail('Running Firebase CLI command:');
      logger.detail('  $command');
      logger.info('');

      // Run upload with timeout
      final results = await _shell.run(command).timeout(
        Duration(seconds: timeout),
        onTimeout: () {
          throw TimeoutException(
            'Firebase upload timed out after $timeout seconds',
          );
        },
      );

      // Check result and collect output
      for (final result in results) {
        // Capture stdout and stderr
        if (result.stdout.isNotEmpty) {
          outputBuffer.writeln('STDOUT:');
          outputBuffer.writeln(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          outputBuffer.writeln('STDERR:');
          outputBuffer.writeln(result.stderr);
        }

        if (result.exitCode != 0) {
          logger.err('');
          logger.err('Firebase CLI exited with code: ${result.exitCode}');
          if (result.stderr.isNotEmpty) {
            logger.err('Error output:');
            logger.err(result.stderr.toString());
          }
          return (success: false, output: outputBuffer.toString());
        }
      }

      return (success: true, output: outputBuffer.toString());
    } on TimeoutException {
      rethrow; // Let the caller handle timeout
    } catch (e) {
      logger.err('');
      logger.err('Firebase upload error: $e');
      logger.err('');

      // Capture error in output
      outputBuffer.writeln('ERROR:');
      outputBuffer.writeln(e.toString());

      // Provide helpful error messages based on common errors
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('permission') || errorStr.contains('unauthorized')) {
        logger.info('💡 This looks like a permission error. Try:');
        logger.info('   1. Run: firebase login');
        logger.info('   2. Or set FIREBASE_TOKEN environment variable');
        logger.info('   3. Or create .firebase-token file in project root');
      } else if (errorStr.contains('not found') || errorStr.contains('no such file')) {
        logger.info('💡 Firebase CLI command not found. Install it with:');
        logger.info('   npm install -g firebase-tools');
      } else if (errorStr.contains('app') && errorStr.contains('not found')) {
        logger.info('💡 App ID not found in Firebase project. Verify:');
        logger.info('   1. App ID is correct in build.yaml');
        logger.info('   2. App exists in Firebase Console');
        logger.info('   3. You have access to the Firebase project');
      } else if (errorStr.contains('network') || errorStr.contains('connection')) {
        logger.info('💡 Network error. Check:');
        logger.info('   1. Internet connection');
        logger.info('   2. Firewall settings');
        logger.info('   3. VPN if required');
      }
      logger.err('');

      return (success: false, output: outputBuffer.toString());
    }
  }

  /// Get Firebase project ID from .firebaserc if exists
  Future<String?> getFirebaseProjectId() async {
    try {
      final basePath = projectPath ?? Directory.current.path;
      final firebaseRc = File(path.join(basePath, '.firebaserc'));

      if (!await firebaseRc.exists()) return null;

      final content = await firebaseRc.readAsString();

      // Simple parsing for default project
      final match = RegExp(r'"default"\s*:\s*"([^"]+)"').firstMatch(content);
      return match?.group(1);
    } catch (e) {
      return null;
    }
  }

  /// Load Firebase token from .firebase-token file if exists
  Future<String?> loadFirebaseToken() async {
    try {
      final basePath = projectPath ?? Directory.current.path;
      final tokenFile = File(path.join(basePath, '.firebase-token'));

      if (!await tokenFile.exists()) return null;

      final token = await tokenFile.readAsString();
      return token.trim();
    } catch (e) {
      return null;
    }
  }

  /// Save Firebase token to .firebase-token file
  Future<void> saveFirebaseToken(String token) async {
    try {
      final basePath = projectPath ?? Directory.current.path;
      final tokenFile = File(path.join(basePath, '.firebase-token'));

      await tokenFile.writeAsString(token.trim());
      logger.detail('✅ Token saved to .firebase-token');

      // Add to .gitignore
      await _addToGitignore('.firebase-token');
    } catch (e) {
      logger.warn('⚠️  Failed to save token: $e');
    }
  }

  /// Add file to .gitignore if not already present
  Future<void> _addToGitignore(String filename) async {
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
      if (lines.any((line) => line.trim() == filename)) {
        logger.detail('✅ $filename already in .gitignore');
        return;
      }

      // Add to .gitignore
      if (content.isNotEmpty && !content.endsWith('\n')) {
        content += '\n';
      }
      content += '# Firebase token (auto-generated by pipo_firebase)\n';
      content += '$filename\n';

      await gitignoreFile.writeAsString(content);
      logger.detail('✅ Added $filename to .gitignore');
    } catch (e) {
      logger.detail('⚠️  Could not update .gitignore: $e');
    }
  }

  /// Check if user has access to Firebase project
  Future<bool> checkProjectAccess(String projectId, {String? token}) async {
    try {
      final command = token != null
          ? 'firebase projects:list --token "$token"'
          : 'firebase projects:list';

      final results = await _shell.run(command);

      // Check if project is in the list
      for (final result in results) {
        if (result.stdout.toString().contains(projectId)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      logger.detail('Failed to check project access: $e');
      return false;
    }
  }

  /// Interactive Firebase login and token generation
  Future<String?> interactiveLogin(String projectId) async {
    logger.info('');
    logger.info('╔══════════════════════════════════════════════════════════════╗');
    logger.info('║              🔐 Firebase Authentication Required              ║');
    logger.info('╚══════════════════════════════════════════════════════════════╝');
    logger.info('');
    logger.info('You need to authenticate with Firebase to access project:');
    logger.info('   Project ID: $projectId');
    logger.info('');

    // Show login options
    logger.info('Choose authentication method:');
    logger.info('   1. Auto-login (Browser will open automatically)');
    logger.info('   2. Manual login (You open browser manually and paste token)');
    logger.info('   3. Skip (Continue without upload)');
    logger.info('');
    stdout.write('Enter your choice (1/2/3): ');
    final choice = stdin.readLineSync()?.trim() ?? '1';

    if (choice == '3') {
      logger.info('');
      logger.info('⏭️  Skipping authentication');
      return null;
    }

    if (choice == '2') {
      return await _manualLogin(projectId);
    }

    // Option 1: Auto-login
    return await _autoLogin(projectId);
  }

  /// Auto-login by opening browser
  Future<String?> _autoLogin(String projectId) async {
    // Check if we're in an interactive environment
    if (!stdin.hasTerminal) {
      logger.warn('⚠️  Non-interactive environment detected');
      logger.info('   Auto-login requires interactive terminal');
      logger.info('');
      logger.info('💡 Using manual login instead');
      return await _manualLogin(projectId);
    }

    try {
      logger.info('');
      logger.info('🌐 Opening browser for authentication...');
      logger.info('');

      // Use runInShell for better compatibility with interactive processes
      final process = await Process.start(
        'firebase',
        ['login'],
        mode: ProcessStartMode.inheritStdio,
      );

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        logger.err('');
        logger.err('❌ Auto-login failed');
        logger.info('');
        logger.info('💡 Try manual login instead');
        return await _manualLogin(projectId);
      }

      logger.info('');
      logger.success('✅ Successfully authenticated with Firebase!');
      logger.info('');

      // Check if user has access to project
      logger.info('🔍 Verifying access to project $projectId...');

      final hasAccess = await checkProjectAccess(projectId);
      if (!hasAccess) {
        logger.err('');
        logger.err('❌ The authenticated account does not have access to project: $projectId');
        logger.err('');
        logger.info('The project is not available in your current Firebase account.');
        logger.info('');
        logger.info('Would you like to switch to a different Google account?');
        logger.info('   1. Yes, open browser to login with different account');
        logger.info('   2. No, skip authentication');
        logger.info('');
        stdout.write('Enter your choice (1/2): ');
        final switchChoice = stdin.readLineSync()?.trim() ?? '2';

        if (switchChoice == '1') {
          logger.info('');
          logger.info('🔄 Switching Firebase account...');
          logger.info('');

          // Logout from current account
          try {
            await _shell.run('firebase logout');
            logger.info('✅ Logged out from current account');
            logger.info('');
          } catch (e) {
            logger.detail('Could not logout: $e');
          }

          // Login with different account
          logger.info('🌐 Opening browser to login with different account...');
          logger.info('   Please select the Google account that has access to:');
          logger.info('   Project: $projectId');
          logger.info('');

          final reloginProcess = await Process.start(
            'firebase',
            ['login'],
            mode: ProcessStartMode.inheritStdio,
          );

          final reloginExitCode = await reloginProcess.exitCode;

          if (reloginExitCode != 0) {
            logger.err('');
            logger.err('❌ Login failed');
            logger.info('');
            return null;
          }

          logger.info('');
          logger.success('✅ Successfully logged in!');
          logger.info('');

          // Verify access again
          logger.info('🔍 Verifying access to project $projectId...');
          final hasAccessNow = await checkProjectAccess(projectId);

          if (!hasAccessNow) {
            logger.err('');
            logger.err('❌ Still no access to project: $projectId');
            logger.err('');
            logger.info('💡 Please ensure:');
            logger.info('   1. You selected the correct Google account');
            logger.info('   2. That account has access to the project');
            logger.info('   3. The project ID in build.yaml is correct');
            logger.info('');
            return null;
          }

          logger.success('✅ Access verified!');
          logger.info('');

          // Continue to generate token
        } else {
          logger.info('');
          logger.info('⏭️  Skipping authentication');
          return null;
        }
      }

      logger.success('✅ Access verified!');
      logger.info('');

      // Generate CI token
      return await _generateAndSaveToken(projectId);
    } catch (e) {
      logger.err('');
      logger.err('❌ Auto-login failed: $e');
      logger.info('');
      logger.info('💡 Let\'s try manual login instead');
      logger.info('');
      return await _manualLogin(projectId);
    }
  }

  /// Manual login by providing instructions
  Future<String?> _manualLogin(String projectId) async {
    try {
      logger.info('');
      logger.info('╔══════════════════════════════════════════════════════════════╗');
      logger.info('║                    📝 Manual Login Steps                      ║');
      logger.info('╚══════════════════════════════════════════════════════════════╝');
      logger.info('');
      logger.info('Please follow these steps:');
      logger.info('');
      logger.info('1. Open this URL in your browser:');
      logger.info('   https://console.firebase.google.com/project/$projectId/overview');
      logger.info('');
      logger.info('2. Login with your Google account that has access to this project');
      logger.info('');
      logger.info('3. Open terminal and run this command:');
      logger.info('   firebase login:ci');
      logger.info('');
      logger.info('4. Copy the token from the output');
      logger.info('');
      logger.info('5. Come back here and paste the token');
      logger.info('');
      stdout.write('Paste your Firebase token here (or press Enter to skip): ');
      final token = stdin.readLineSync()?.trim();

      if (token == null || token.isEmpty) {
        logger.info('');
        logger.info('⏭️  Skipping authentication');
        return null;
      }

      // Validate token
      logger.info('');
      logger.info('🔍 Validating token...');
      final hasAccess = await checkProjectAccess(projectId, token: token);

      if (!hasAccess) {
        logger.err('');
        logger.err('❌ Invalid token or no access to project: $projectId');
        logger.err('');
        logger.info('💡 Please try again with a valid token');
        logger.info('');
        return null;
      }

      logger.success('✅ Token is valid!');
      logger.info('');

      // Save token
      await saveFirebaseToken(token);

      logger.success('✅ Token saved to .firebase-token');
      logger.info('');
      logger.info('✨ You won\'t need to login again for this project.');
      logger.info('');

      return token;
    } catch (e) {
      logger.err('');
      logger.err('❌ Manual login failed: $e');
      logger.info('');
      return null;
    }
  }

  /// Generate and save Firebase CI token
  Future<String?> _generateAndSaveToken(String projectId) async {
    // Check if we're in an interactive environment
    if (!stdin.hasTerminal) {
      logger.info('ℹ️  Non-interactive environment detected');
      logger.info('   Skipping token generation');
      logger.info('   You can generate token manually with: firebase login:ci');
      logger.info('');
      return null; // User can still use the session login
    }

    try {
      logger.info('🔑 Generating authentication token for persistent storage...');
      logger.info('   This will open a browser window');
      logger.info('');

      // Use Process.start with inheritStdio for interactive token generation
      final process = await Process.start(
        'firebase',
        ['login:ci'],
        mode: ProcessStartMode.inheritStdio,
      );

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        logger.info('');
        logger.warn('⚠️  Token generation skipped or failed');
        logger.info('   No worries! You\'re already logged in and can upload.');
        logger.info('   To generate token later, run: firebase login:ci');
        logger.info('');
        return null;
      }

      logger.info('');
      logger.success('✅ Token generated successfully!');
      logger.info('');
      logger.info('ℹ️  The token should be displayed above.');
      logger.info('   Copy and paste it here to save to .firebase-token file');
      logger.info('   (or press Enter to skip - you can still upload using current session)');
      logger.info('');
      stdout.write('Paste token here (optional): ');
      final token = stdin.readLineSync()?.trim();

      if (token != null && token.isNotEmpty) {
        // Validate the token format (Firebase tokens start with "1//")
        if (token.startsWith('1//')) {
          await saveFirebaseToken(token);
          logger.info('');
          logger.success('✅ Token saved to .firebase-token');
          logger.info('✨ You won\'t need to login again for this project!');
          logger.info('');
          return token;
        } else {
          logger.warn('');
          logger.warn('⚠️  Invalid token format (should start with "1//")');
          logger.info('   Continuing without saving token...');
          logger.info('');
          return null;
        }
      }

      logger.info('');
      logger.info('⏭️  Token not saved');
      logger.info('   You can still upload using your current Firebase login session.');
      logger.info('');
      return null;
    } catch (e) {
      logger.info('');
      logger.warn('⚠️  Could not generate token: $e');
      logger.info('   No worries! You\'re already logged in and can upload.');
      logger.info('');
      return null;
    }
  }

  /// Ensure user has valid Firebase authentication
  Future<String?> ensureAuthentication(String projectId, String? token) async {
    // Try existing token first
    if (token != null && token.isNotEmpty) {
      logger.detail('🔍 Checking existing token...');

      final hasAccess = await checkProjectAccess(projectId, token: token);
      if (hasAccess) {
        logger.detail('✅ Token is valid');
        return token;
      }

      logger.warn('⚠️  Existing token is invalid or expired');
    }

    // Try loading token from file
    final savedToken = await loadFirebaseToken();
    if (savedToken != null && savedToken.isNotEmpty) {
      logger.detail('🔍 Checking saved token from .firebase-token...');

      final hasAccess = await checkProjectAccess(projectId, token: savedToken);
      if (hasAccess) {
        logger.detail('✅ Saved token is valid');
        return savedToken;
      }

      logger.warn('⚠️  Saved token is invalid or expired');
    }

    // Check if already logged in (no token)
    logger.detail('🔍 Checking if already logged in to Firebase...');
    final hasAccess = await checkProjectAccess(projectId);
    if (hasAccess) {
      logger.detail('✅ Already logged in with valid access');
      return null; // Use default login
    }

    // Need to login
    logger.info('');
    logger.warn('⚠️  No valid Firebase authentication found');

    return await interactiveLogin(projectId);
  }
}
