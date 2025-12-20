/// Firebase configuration extracted from google-services.json or GoogleService-Info.plist
class FirebaseConfig {
  /// Firebase project ID
  final String projectId;

  /// Firebase project number
  final String projectNumber;

  /// Firebase app ID (mobilesdk_app_id for Android, GOOGLE_APP_ID for iOS)
  final String appId;

  /// Bundle ID / Package name
  final String bundleId;

  /// Platform (android or ios)
  final String platform;

  /// Environment name (e.g., dev, staging, production)
  final String? environment;

  /// Storage bucket
  final String? storageBucket;

  const FirebaseConfig({
    required this.projectId,
    required this.projectNumber,
    required this.appId,
    required this.bundleId,
    required this.platform,
    this.environment,
    this.storageBucket,
  });

  @override
  String toString() {
    return 'FirebaseConfig('
        'projectId: $projectId, '
        'projectNumber: $projectNumber, '
        'appId: $appId, '
        'bundleId: $bundleId, '
        'platform: $platform, '
        'environment: $environment'
        ')';
  }

  /// Convert to a map for YAML generation
  Map<String, dynamic> toMap() {
    return {
      'project_id': projectId,
      'project_number': projectNumber,
      'app_id': appId,
      'bundle_id': bundleId,
      'platform': platform,
      if (environment != null) 'environment': environment,
      if (storageBucket != null) 'storage_bucket': storageBucket,
    };
  }
}
