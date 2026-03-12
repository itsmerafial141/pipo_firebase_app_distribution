# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dart CLI tool (`pipo_firebase`) that automates building and uploading Flutter APK/IPA files to Firebase App Distribution. It auto-detects Firebase configuration from `google-services.json` and `GoogleService-Info.plist` files, generates a `build.yaml` config, and handles the full build-upload-tag lifecycle.

## Development Commands

```bash
# Install dependencies
dart pub get

# Run the CLI locally
dart run bin/pipo_firebase_app_distribution.dart init
dart run bin/pipo_firebase_app_distribution.dart deploy dev --platform android

# Run all tests
dart test

# Run a single test file
dart test test/<test_file>.dart

# Analyze code (uses package:lints/recommended.yaml)
dart analyze

# Format code
dart format .

# Activate globally for testing
dart pub global activate --source path .
```

## SDK

This project uses FVM with Flutter 3.35.5. Dart SDK constraint: `^3.9.2`.

## Architecture

The CLI has two commands routed via a switch in `bin/pipo_firebase_app_distribution.dart`:

### `init` command flow
`InitCommand` → `AndroidConfigExtractor` + `IosConfigExtractor` → list of `FirebaseConfig` → `BuildYamlTemplate.generate()` → writes `build.yaml`

- **AndroidConfigExtractor**: Reads `google-services.json` files, uses `GradleParser` to extract product flavors from `build.gradle`, and matches Firebase clients to flavors by `applicationId`.
- **IosConfigExtractor**: Reads `GoogleService-Info.plist` XML files, detects environments from directory paths (e.g., `Firebase/dev/`).
- **FirebaseConfig**: Platform-agnostic data class holding projectId, appId, bundleId, platform, environment.

### `deploy` command flow
`DeployCommand` → `BuildYamlParser.parse()` → `BuildConfig` → version increment → build → release notes → upload → git tag

Key participants:
- **BuildYamlParser**: Parses `build.yaml` into `BuildConfig` (the central config model with nested types: `EnvironmentConfig`, `SetupConfig`, `PlatformsConfig`, etc.)
- **FlutterBuilder**: Shells out to `flutter build apk/ipa` with flavor and build mode args. Returns `BuildResult` with artifact path.
- **FirebaseAuth** (`auth/`): Handles service account JWT creation (RSA-SHA256 via `pointycastle`), exchanges for OAuth2 access token. Credentials resolved from: `build.yaml` `credentials_file` → `GOOGLE_APPLICATION_CREDENTIALS` env var → `.firebase-credentials.json` in project root.
- **FirebaseUploader**: Calls Firebase App Distribution REST API directly (upload binary → update release notes → distribute to groups). No Firebase CLI required. Returns `UploadResult`.
- **VersionManager**: Reads/writes `pubspec.yaml` to increment the build number.
- **GitHelper**: Creates tags (`appdist-{env}-{version}`), generates release notes from commits since last tag, commits version bumps, and pushes.
- **ErrorLogger**: Writes error logs to `.pipo_logs/` directory.

### Data model hierarchy (`build_config.dart`)
`BuildConfig` is the root model parsed from `build.yaml`:
- `ProjectConfig` (name, version)
- `FirebaseConfigInfo` (projectId, projectNumber, timeout, credentialsFile)
- `Map<String, EnvironmentConfig>` — per-environment settings, each containing app IDs per platform, distribution group, and `SetupConfig` (buildMode, upload, obfuscate, autoIncrement, clean)
- `PlatformsConfig` → `AndroidPlatformConfig` (buildFormat: apk/aab) + `IosPlatformConfig` (exportMethod, teamId)

### Key distinction
`FirebaseConfig` (in `config/`) is the raw extracted data from Firebase config files (used during `init`). `BuildConfig` (in `parser/`) is the parsed `build.yaml` structure (used during `deploy`). They are separate models for separate phases.

## Conventions

- CLI output uses `mason_logger` (`Logger`) — use `logger.info`, `logger.err`, `logger.success`, `logger.progress`, `logger.confirm`.
- Shell commands (flutter build, git) use `process_run` package. HTTP API calls (Firebase upload, OAuth2) use `http` package.
- All commands accept an optional `projectPath` parameter (defaults to `Directory.current.path`) to support testing.
- Config extractors and parsers are static-method-based classes, not instantiated.
- The executable is registered as `pipo_firebase` in `pubspec.yaml` (maps to `bin/pipo_firebase_app_distribution.dart`).
