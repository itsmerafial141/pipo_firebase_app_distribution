# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.3] - 2026-03-12

### Added
- **FVM support**: `use_fvm` option in `build.yaml` under `project` section
  ```yaml
  project:
    name: "my_app"
    version: "1.0.0+1"
    use_fvm: true
  ```
  When enabled, all Flutter commands (`clean`, `pub get`, `build`) are prefixed with `fvm`.

---

## [0.0.2] - 2026-03-12

### Added
- **Multiple tester groups**: `groups` field now supports array of group aliases per environment
  ```yaml
  groups:
    - "internal-tester"
    - "external-tester"
  ```
  Backward-compatible with legacy `group: "single-group"` format.

- **Custom build args**: `extra_args`, `android_extra_args`, and `ios_extra_args` per environment
  ```yaml
  setup:
    extra_args: ["--dart-define=ENV=dev"]
    android_extra_args: ["--split-per-abi"]
    ios_extra_args: ["--export-method=ad-hoc"]
  ```

### Improved
- **Service account authentication**: Direct REST API upload — no Firebase CLI required
- **Distribution logging**: Shows distribute API response for easier debugging when group assignment fails
- **Deploy flow**: Build → Upload per platform (prevents `flutter clean` from deleting previous platform artifact)
- **Skip build behavior**: `--skip-build` no longer increments version since the existing build already has the correct version

### Fixed
- Auto-assign testers/groups after upload now logs success/failure with actionable tips
- `--platform` flag properly registered in argument parser

---

## [0.0.1] - 2024-01-15

### ✨ Features

#### Configuration Management
- **Auto-Detection**: Automatically scans and extracts Firebase configuration from:
  - `google-services.json` (Android)
  - `android/app/src/{flavor}/google-services.json` (Flavor-specific)
  - `GoogleService-Info.plist` (iOS)
  - `ios/Runner/Firebase/{flavor}/GoogleService-Info.plist` (Flavor-specific)

- **Smart Template Generation**: Generates complete `build.yaml` configuration file with:
  - Project information from `pubspec.yaml`
  - All detected Firebase App IDs (Android & iOS)
  - Environment-specific settings (dev, staging, production)
  - Build presets for common workflows
  - Platform-specific configurations

- **Product Flavor Detection**: Reads Android product flavors from `build.gradle`:
  - Extracts `productFlavors` configuration
  - Gets `applicationId` for each flavor
  - Matches flavors with Firebase clients
  - Only includes configured flavors (ignores extra clients)

#### Build Automation
- **Automated Build Process**: Single command to build apps for distribution:
  - Flutter build integration (`flutter build apk/ipa`)
  - Support for both Android (APK/AAB) and iOS (IPA)
  - Flavor-specific builds (e.g., `--flavor dev`)
  - Build mode selection (debug/release)
  - Code obfuscation support

- **Build Configuration**:
  - Clean build option
  - Custom symbols directory for obfuscation
  - Platform-specific build formats
  - Build artifact detection and validation

#### Firebase App Distribution
- **Upload Automation**: Seamless upload to Firebase App Distribution:
  - Firebase CLI integration
  - Distribution groups configuration
  - Release notes attachment
  - Timeout configuration
  - Upload validation

- **Release Notes**: Auto-generated from git commits:
  - Commits since last tag
  - Environment and build mode info
  - Version number
  - Customizable format

#### Authentication
- **Smart Firebase Authentication**:
  - Auto-login with browser (recommended)
  - Manual token input option
  - Multi-account support with account switching
  - Persistent token storage in `.firebase-token`
  - Token validation and auto-refresh
  - Project access verification

- **Authentication Flow**:
  - Interactive login prompts
  - Account switching when no access
  - Token generation with `firebase login:ci`
  - Token saved locally (auto-gitignored)

#### Version Management
- **Auto-Increment**: Automatic version number management:
  - Build number increment (e.g., 1.0.0+1 → 1.0.0+2)
  - `pubspec.yaml` update
  - Configurable per environment

#### Git Integration
- **Git Operations**:
  - Auto-commit version changes
  - Git tag creation (e.g., `v1.0.0-dev+2`)
  - Release tracking
  - Commit history for release notes

#### Error Handling
- **Comprehensive Error Logging**:
  - Build errors logged to `.pipo_logs/build_{platform}_{env}_{timestamp}.log`
  - Upload errors logged to `.pipo_logs/upload_{platform}_{env}_{timestamp}.log`
  - Deployment errors logged to `.pipo_logs/deployment_{env}_{timestamp}.log`
  - Auto-gitignore for log directory
  - Detailed error messages with troubleshooting tips

#### Multi-Environment Support
- **Environment Detection**:
  - From file paths (e.g., `src/dev/`, `Firebase/staging/`)
  - From bundle IDs (e.g., `com.example.app.dev`)
  - From product flavors in `build.gradle`
  - Supported environments: dev, development, staging, qa, production, prod

- **Per-Environment Configuration**:
  - Build mode (debug/release)
  - Upload settings
  - Code obfuscation
  - Version auto-increment
  - Distribution groups
  - Platform-specific settings

#### Platform Support
- **Android**:
  - APK and AAB build formats
  - Product flavor support
  - Gradle parser for flavor detection
  - `applicationId` and `applicationIdSuffix` handling
  - Multiple `google-services.json` support

- **iOS**:
  - IPA build support
  - Export method configuration (development, app-store, ad-hoc, enterprise)
  - Multiple `GoogleService-Info.plist` support
  - Bundle ID detection

### 🛠️ CLI Commands

#### `init` Command
```bash
pipo_firebase init
```
- Scans Firebase configuration files
- Extracts product flavors from `build.gradle`
- Matches flavors with Firebase clients
- Generates `build.yaml` template
- Includes project info from `pubspec.yaml`

#### `deploy` Command
```bash
pipo_firebase deploy <environment> [options]
```

**Options:**
- `--platform, -p`: Platform to build (`android`, `ios`, or `both`)
- `--skip-build`: Skip building the app
- `--skip-upload`: Skip uploading to Firebase
- `--skip-version-increment`: Skip incrementing version number
- `--skip-git-tag`: Skip creating git tags
- `--help, -h`: Show help for deploy command

**What it does:**
1. Reads build configuration from `build.yaml`
2. Auto-increments version number (if configured)
3. Builds APK/IPA for specified platform(s)
4. Generates release notes from git commits
5. Uploads to Firebase App Distribution
6. Creates git tags and commits changes

**Examples:**
```bash
# Deploy dev environment (both platforms)
pipo_firebase deploy dev

# Deploy only Android
pipo_firebase deploy dev --platform android

# Deploy only iOS
pipo_firebase deploy staging --platform ios

# Build without uploading
pipo_firebase deploy dev --skip-upload

# Upload existing build
pipo_firebase deploy dev --skip-build
```

### 📦 Core Components

#### Configuration Extractors
- `AndroidConfigExtractor`: Parses `google-services.json` files
- `IosConfigExtractor`: Parses `GoogleService-Info.plist` files
- `GradleParser`: Extracts product flavors from `build.gradle`

#### Build System
- `FlutterBuilder`: Handles Flutter build operations
- `BuildYamlParser`: Parses `build.yaml` configuration
- `BuildConfig`: Configuration data models

#### Upload System
- `FirebaseUploader`: Firebase App Distribution upload
- Firebase CLI integration
- Authentication management
- Upload validation

#### Utilities
- `VersionManager`: Version number management
- `GitHelper`: Git operations and release notes
- `ErrorLogger`: Error logging and reporting
- `PubspecReader`: Project info extraction

### 🎨 Generated Files

#### `build.yaml`
Complete build configuration with:
- Project information
- Firebase configuration (project ID, project number)
- Environment configurations (dev, staging, production)
- Build presets (quick-dev, test-build, production-release)
- Default settings
- Platform-specific settings

#### `.firebase-token`
- Auto-generated Firebase authentication token
- Automatically added to `.gitignore`
- Used for Firebase CLI authentication

#### `.pipo_logs/`
- Error logs directory
- Build, upload, and deployment logs
- Automatically added to `.gitignore`
- Timestamped log files

### 🔒 Security

- Firebase token auto-gitignored
- Error logs auto-gitignored
- No sensitive data in generated files
- Token validation before use
- Project access verification

### 📚 Documentation

- Comprehensive README with:
  - Installation instructions
  - Quick start guide
  - Command reference
  - Authentication guide
  - Troubleshooting section
  - Advanced usage examples
  - Platform-specific configuration

- Inline documentation:
  - Detailed code comments
  - Usage examples
  - Error messages with solutions

### 🐛 Bug Fixes

- Fixed regex syntax errors in `GradleParser`
- Fixed flavor detection to only include configured flavors
- Fixed multi-account authentication flow
- Fixed token storage and validation

### 🚀 Performance

- Fast Firebase configuration scanning
- Efficient flavor detection
- Parallel tool execution where possible
- Optimized build artifact detection

### 💡 Improvements

- Better error messages with actionable solutions
- Colorful CLI output with mason_logger
- Progress indicators for long-running operations
- Interactive prompts for authentication
- Detailed deployment summary

### 📝 Notes

This is the initial release of `pipo_firebase_app_distribution`. The package provides a complete solution for automating Firebase App Distribution deployments with smart configuration detection and seamless integration with your Flutter project.

**Command Shortcuts:**
- Global install: `pipo_firebase deploy dev`
- Local install: `dart run pipo_firebase deploy dev`

**Requirements:**
- Flutter SDK installed
- Firebase CLI installed (`npm install -g firebase-tools`)
- Firebase project with App Distribution enabled
- Firebase configuration files in your project

**Getting Started:**
1. Install the CLI: `dart pub global activate pipo_firebase_app_distribution`
2. Initialize: `pipo_firebase init`
3. Review and customize `build.yaml`
4. Deploy: `pipo_firebase deploy dev`

For more information, visit: https://pub.dev/packages/pipo_firebase_app_distribution

---

## [Unreleased]

### Planned Features
- Support for multiple Firebase projects
- CI/CD integration examples
- GitHub Actions workflow templates
- Support for iOS schemes (similar to Android flavors)
- Release notes templates
- Slack/Discord notifications
- Build presets execution
- Custom hooks support

[0.0.3]: https://github.com/yourusername/pipo_firebase_app_distribution/releases/tag/v0.0.3
[0.0.2]: https://github.com/yourusername/pipo_firebase_app_distribution/releases/tag/v0.0.2
[0.0.1]: https://github.com/yourusername/pipo_firebase_app_distribution/releases/tag/v0.0.1
