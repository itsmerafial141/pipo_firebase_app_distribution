/// A Dart CLI tool to automatically upload APK/IPA to Firebase App Distribution
/// with auto-detection of Firebase configuration from google-services.json
/// and GoogleService-Info.plist
library;

// Auth exports
export 'src/auth/firebase_auth.dart';

// Config exports
export 'src/config/firebase_config.dart';
export 'src/config/android_config_extractor.dart';
export 'src/config/ios_config_extractor.dart';

// Parser exports
export 'src/parser/build_config.dart';
export 'src/parser/build_yaml_parser.dart';

// Builder exports
export 'src/builder/flutter_builder.dart';

// Uploader exports
export 'src/uploader/firebase_uploader.dart';

// Utils exports
export 'src/utils/pubspec_reader.dart';
export 'src/utils/version_manager.dart';
export 'src/utils/git_helper.dart';
export 'src/utils/deploy_logger.dart';

// Template exports
export 'src/templates/build_yaml_template.dart';

// Command exports
export 'src/commands/init_command.dart';
export 'src/commands/deploy_command.dart';
