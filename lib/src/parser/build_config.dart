/// Build configuration model parsed from build.yaml
class BuildConfig {
  final ProjectConfig project;
  final FirebaseConfigInfo firebase;
  final Map<String, EnvironmentConfig> environments;
  final Map<String, PresetConfig> presets;
  final DefaultsConfig defaults;
  final PlatformsConfig platforms;

  BuildConfig({
    required this.project,
    required this.firebase,
    required this.environments,
    required this.presets,
    required this.defaults,
    required this.platforms,
  });

  factory BuildConfig.fromMap(Map<String, dynamic> map) {
    return BuildConfig(
      project: ProjectConfig.fromMap(map['project'] as Map<String, dynamic>),
      firebase: FirebaseConfigInfo.fromMap(map['firebase'] as Map<String, dynamic>),
      environments: (map['environments'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          EnvironmentConfig.fromMap(value as Map<String, dynamic>),
        ),
      ),
      presets: (map['presets'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          PresetConfig.fromMap(value as Map<String, dynamic>),
        ),
      ),
      defaults: DefaultsConfig.fromMap(map['defaults'] as Map<String, dynamic>),
      platforms: PlatformsConfig.fromMap(map['platforms'] as Map<String, dynamic>),
    );
  }
}

class ProjectConfig {
  final String name;
  final String version;

  ProjectConfig({
    required this.name,
    required this.version,
  });

  factory ProjectConfig.fromMap(Map<String, dynamic> map) {
    return ProjectConfig(
      name: map['name'] as String,
      version: map['version'] as String,
    );
  }
}

class FirebaseConfigInfo {
  final String projectId;
  final String projectNumber;
  final int timeout;

  FirebaseConfigInfo({
    required this.projectId,
    required this.projectNumber,
    required this.timeout,
  });

  factory FirebaseConfigInfo.fromMap(Map<String, dynamic> map) {
    return FirebaseConfigInfo(
      projectId: map['project_id'] as String,
      projectNumber: map['project_number'] as String,
      timeout: map['timeout'] as int,
    );
  }
}

class EnvironmentConfig {
  final String? androidAppId;
  final String? androidBundleId;
  final String? iosAppId;
  final String? iosBundleId;
  final String? group;
  final SetupConfig setup;

  EnvironmentConfig({
    this.androidAppId,
    this.androidBundleId,
    this.iosAppId,
    this.iosBundleId,
    this.group,
    required this.setup,
  });

  factory EnvironmentConfig.fromMap(Map<String, dynamic> map) {
    return EnvironmentConfig(
      androidAppId: map['android_app_id'] as String?,
      androidBundleId: map['android_bundle_id'] as String?,
      iosAppId: map['ios_app_id'] as String?,
      iosBundleId: map['ios_bundle_id'] as String?,
      group: map['group'] as String?,
      setup: SetupConfig.fromMap(map['setup'] as Map<String, dynamic>),
    );
  }
}

class SetupConfig {
  final String buildMode; // release or debug
  final bool upload;
  final bool obfuscate;
  final bool autoIncrement;
  final bool clean;

  SetupConfig({
    required this.buildMode,
    required this.upload,
    required this.obfuscate,
    required this.autoIncrement,
    required this.clean,
  });

  factory SetupConfig.fromMap(Map<String, dynamic> map) {
    return SetupConfig(
      buildMode: map['build_mode'] as String,
      upload: map['upload'] as bool,
      obfuscate: map['obfuscate'] as bool,
      autoIncrement: map['auto_increment'] as bool,
      clean: map['clean'] as bool,
    );
  }
}

class PresetConfig {
  final String environment;
  final String buildMode;
  final bool upload;
  final bool clean;
  final bool? increment;

  PresetConfig({
    required this.environment,
    required this.buildMode,
    required this.upload,
    required this.clean,
    this.increment,
  });

  factory PresetConfig.fromMap(Map<String, dynamic> map) {
    return PresetConfig(
      environment: map['environment'] as String,
      buildMode: map['build_mode'] as String,
      upload: map['upload'] as bool,
      clean: map['clean'] as bool,
      increment: map['increment'] as bool?,
    );
  }
}

class DefaultsConfig {
  final String buildMode;
  final bool upload;
  final bool clean;
  final bool autoIncrement;
  final bool obfuscate;

  DefaultsConfig({
    required this.buildMode,
    required this.upload,
    required this.clean,
    required this.autoIncrement,
    required this.obfuscate,
  });

  factory DefaultsConfig.fromMap(Map<String, dynamic> map) {
    return DefaultsConfig(
      buildMode: map['build_mode'] as String,
      upload: map['upload'] as bool,
      clean: map['clean'] as bool,
      autoIncrement: map['auto_increment'] as bool,
      obfuscate: map['obfuscate'] as bool,
    );
  }
}

class PlatformsConfig {
  final AndroidPlatformConfig android;
  final IosPlatformConfig ios;

  PlatformsConfig({
    required this.android,
    required this.ios,
  });

  factory PlatformsConfig.fromMap(Map<String, dynamic> map) {
    return PlatformsConfig(
      android: AndroidPlatformConfig.fromMap(map['android'] as Map<String, dynamic>),
      ios: IosPlatformConfig.fromMap(map['ios'] as Map<String, dynamic>),
    );
  }
}

class AndroidPlatformConfig {
  final String buildFormat; // apk or aab
  final String? flavorDimension;

  AndroidPlatformConfig({
    required this.buildFormat,
    this.flavorDimension,
  });

  factory AndroidPlatformConfig.fromMap(Map<String, dynamic> map) {
    return AndroidPlatformConfig(
      buildFormat: map['build_format'] as String,
      flavorDimension: map['flavor_dimension'] as String?,
    );
  }
}

class IosPlatformConfig {
  final String exportMethod; // development, app-store, ad-hoc, enterprise
  final String? teamId;

  IosPlatformConfig({
    required this.exportMethod,
    this.teamId,
  });

  factory IosPlatformConfig.fromMap(Map<String, dynamic> map) {
    return IosPlatformConfig(
      exportMethod: map['export_method'] as String,
      teamId: map['team_id'] as String?,
    );
  }
}
