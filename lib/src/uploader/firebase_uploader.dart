import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../auth/firebase_auth.dart';

/// Firebase upload configuration
class UploadOptions {
  final String artifactPath;
  final String appId;
  final String? releaseNotes;
  final String? groups;
  final String? testers;
  final String projectNumber;
  final int timeout;

  UploadOptions({
    required this.artifactPath,
    required this.appId,
    this.releaseNotes,
    this.groups,
    this.testers,
    required this.projectNumber,
    this.timeout = 600,
  });
}

/// Result of Firebase upload
class UploadResult {
  final bool success;
  final String? error;
  final String? releaseName;
  final String? firebaseOutput;

  UploadResult({
    required this.success,
    this.error,
    this.releaseName,
    this.firebaseOutput,
  });
}

/// Firebase App Distribution uploader using REST API.
///
/// Uses the Firebase App Distribution v1 API directly instead of
/// requiring the Firebase CLI to be installed.
class FirebaseUploader {
  final String? projectPath;
  final Logger logger;
  final FirebaseAuth auth;
  final http.Client _httpClient;

  static const _baseUrl =
      'https://firebaseappdistribution.googleapis.com';
  static const _uploadUrl =
      'https://firebaseappdistribution.googleapis.com/upload';

  FirebaseUploader({
    this.projectPath,
    Logger? logger,
    required this.auth,
    http.Client? httpClient,
  })  : logger = logger ?? Logger(),
        _httpClient = httpClient ?? http.Client();

  /// Upload artifact to Firebase App Distribution via REST API.
  Future<UploadResult> upload(UploadOptions options) async {
    try {
      // Verify artifact exists
      logger.detail('Verifying artifact file...');
      final artifactFile = File(options.artifactPath);
      if (!await artifactFile.exists()) {
        return UploadResult(
          success: false,
          error: 'Artifact file not found: ${options.artifactPath}',
        );
      }
      final artifactSize = await artifactFile.length();
      logger.detail('Artifact found (${_formatSize(artifactSize)})');

      // Get access token
      logger.detail('Authenticating with service account...');
      final accessToken = await auth.getAccessToken();
      logger.detail('Authentication successful');

      // Step 1: Upload binary
      logger.info('📤 Starting upload to Firebase App Distribution...');
      logger.info('   App ID: ${options.appId}');
      if (options.groups != null) {
        logger.info('   Groups: ${options.groups}');
      }
      logger.info('');

      final uploadProgress = logger.progress('⏳ Uploading artifact');

      final releaseName = await _uploadBinary(
        accessToken: accessToken,
        projectNumber: options.projectNumber,
        appId: options.appId,
        artifactFile: artifactFile,
        timeout: options.timeout,
      );

      uploadProgress.complete('✅ Upload completed successfully');

      // Step 2: Update release notes if provided
      if (options.releaseNotes != null && options.releaseNotes!.isNotEmpty) {
        logger.detail('Updating release notes...');
        await _updateReleaseNotes(
          accessToken: accessToken,
          releaseName: releaseName,
          releaseNotes: options.releaseNotes!,
        );
        logger.detail('Release notes updated');
      }

      // Step 3: Distribute to groups/testers
      if ((options.groups != null && options.groups!.isNotEmpty) ||
          (options.testers != null && options.testers!.isNotEmpty)) {
        final distributeProgress = logger.progress('Distributing to testers/groups');
        final distributed = await _distribute(
          accessToken: accessToken,
          releaseName: releaseName,
          groups: options.groups,
          testers: options.testers,
        );
        if (distributed) {
          distributeProgress.complete('✅ Distributed to testers/groups');
        } else {
          distributeProgress.fail('❌ Failed to distribute to testers/groups');
        }
      } else {
        logger.detail('No groups or testers configured, skipping distribution');
      }

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
        releaseName: releaseName,
      );
    } on TimeoutException catch (e) {
      logger.err('⏱️  Upload timeout: $e');
      return UploadResult(
        success: false,
        error: 'Upload timed out after ${options.timeout} seconds.\n'
            'Try increasing timeout in build.yaml or check your network connection.',
      );
    } catch (e, stackTrace) {
      logger.err('💥 Upload failed: $e');
      logger.detail('Stack trace: $stackTrace');
      return UploadResult(
        success: false,
        error: e.toString(),
        firebaseOutput: e.toString(),
      );
    }
  }

  /// Upload binary to Firebase App Distribution.
  ///
  /// POST https://firebaseappdistribution.googleapis.com/upload/v1/projects/{project_number}/apps/{app_id}/releases:upload
  Future<String> _uploadBinary({
    required String accessToken,
    required String projectNumber,
    required String appId,
    required File artifactFile,
    required int timeout,
  }) async {
    final url =
        '$_uploadUrl/v1/projects/$projectNumber/apps/$appId/releases:upload';
    final fileBytes = await artifactFile.readAsBytes();
    final fileName = path.basename(artifactFile.path);

    logger.detail('Uploading to: $url');
    logger.detail('File: $fileName (${_formatSize(fileBytes.length)})');

    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/octet-stream',
            'X-Goog-Upload-File-Name': fileName,
            'X-Goog-Upload-Protocol': 'raw',
          },
          body: fileBytes,
        )
        .timeout(Duration(seconds: timeout));

    if (response.statusCode != 200) {
      throw HttpException(
        'Upload failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;

    // The response contains an operation. If done, extract the release name.
    if (data['done'] == true) {
      final result = data['response'] as Map<String, dynamic>?;
      if (result != null) {
        final release = result['release'] as Map<String, dynamic>?;
        if (release != null) {
          return release['name'] as String;
        }
      }
    }

    // If the operation is not immediately done, poll for completion
    final operationName = data['name'] as String?;
    if (operationName != null) {
      return await _pollOperation(
        accessToken: accessToken,
        operationName: operationName,
        timeout: timeout,
      );
    }

    throw HttpException('Unexpected upload response: ${response.body}');
  }

  /// Poll a long-running operation until it completes.
  Future<String> _pollOperation({
    required String accessToken,
    required String operationName,
    required int timeout,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeout));
    var pollInterval = const Duration(seconds: 2);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);

      final url = '$_baseUrl/v1/$operationName';
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to poll operation (${response.statusCode}): ${response.body}',
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['done'] == true) {
        final error = data['error'] as Map<String, dynamic>?;
        if (error != null) {
          throw HttpException(
            'Upload operation failed: ${error['message'] ?? json.encode(error)}',
          );
        }

        final result = data['response'] as Map<String, dynamic>?;
        if (result != null) {
          final release = result['release'] as Map<String, dynamic>?;
          if (release != null) {
            return release['name'] as String;
          }
        }
        throw HttpException('Upload completed but no release name found');
      }

      // Exponential backoff, capped at 10 seconds
      if (pollInterval.inSeconds < 10) {
        pollInterval = Duration(seconds: pollInterval.inSeconds * 2);
      }
    }

    throw TimeoutException(
      'Upload operation timed out after $timeout seconds',
    );
  }

  /// Update release notes for an uploaded release.
  ///
  /// PATCH https://firebaseappdistribution.googleapis.com/v1/{release_name}?updateMask=releaseNotes.text
  Future<void> _updateReleaseNotes({
    required String accessToken,
    required String releaseName,
    required String releaseNotes,
  }) async {
    final url = '$_baseUrl/v1/$releaseName?updateMask=releaseNotes.text';

    final response = await _httpClient.patch(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'releaseNotes': {'text': releaseNotes},
      }),
    );

    if (response.statusCode != 200) {
      logger.warn(
        '⚠️  Failed to update release notes (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Distribute a release to groups and/or testers.
  ///
  /// POST https://firebaseappdistribution.googleapis.com/v1/{release_name}:distribute
  Future<bool> _distribute({
    required String accessToken,
    required String releaseName,
    String? groups,
    String? testers,
  }) async {
    final url = '$_baseUrl/v1/$releaseName:distribute';

    final body = <String, dynamic>{};
    if (groups != null && groups.isNotEmpty) {
      body['groupAliases'] = groups.split(',').map((g) => g.trim()).toList();
    }
    if (testers != null && testers.isNotEmpty) {
      body['testerEmails'] = testers.split(',').map((t) => t.trim()).toList();
    }

    logger.detail('Distribute request: ${json.encode(body)}');

    final response = await _httpClient.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );

    if (response.statusCode != 200) {
      logger.err(
        '❌ Failed to distribute release (${response.statusCode}): ${response.body}',
      );
      logger.info('');
      logger.info('💡 Tip: Make sure the group alias matches exactly what\'s in Firebase Console.');
      logger.info('   Go to Firebase Console → App Distribution → Testers & Groups to check aliases.');
      return false;
    }
    return true;
  }

  /// Add file to .gitignore if not already present.
  Future<void> addToGitignore(String filename) async {
    try {
      final basePath = projectPath ?? Directory.current.path;
      final gitignoreFile = File(path.join(basePath, '.gitignore'));

      String content = '';
      if (await gitignoreFile.exists()) {
        content = await gitignoreFile.readAsString();
      }

      final lines = content.split('\n');
      if (lines.any((line) => line.trim() == filename)) {
        return;
      }

      if (content.isNotEmpty && !content.endsWith('\n')) {
        content += '\n';
      }
      content += '# Firebase credentials (auto-generated by pipo_firebase)\n';
      content += '$filename\n';

      await gitignoreFile.writeAsString(content);
      logger.detail('Added $filename to .gitignore');
    } catch (e) {
      logger.detail('Could not update .gitignore: $e');
    }
  }

  /// Format file size in human-readable format.
  String _formatSize(int bytes) {
    final sizeInMB = bytes / (1024 * 1024);
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(2)} MB';
    } else {
      final sizeInKB = bytes / 1024;
      return '${sizeInKB.toStringAsFixed(2)} KB';
    }
  }
}
