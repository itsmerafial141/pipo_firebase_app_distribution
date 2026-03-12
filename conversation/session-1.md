# Session 1 - Replace Firebase CLI with REST API

## Date: 2026-03-09

## Summary

Refactored the upload logic from shelling out to Firebase CLI to using the Firebase App Distribution REST API directly.

## Motivation

- Users won't need to install Firebase CLI
- More secure token handling via service account JSON key files
- CI/CD ready (Jenkins integration)
- Token file won't be pushed to git but can be hardcoded for CI/CD

## User Decisions

- **Auth method**: Google Cloud Service Account JSON key file as primary auth
- **HTTP library**: `http` package only (minimal deps, no `googleapis_auth`)
- **Default credentials file**: `.firebase-credentials.json` convention (auto-gitignored)
- **Update scope**: Config, documentation, and README for pub.dev

## Files Created

### `lib/src/auth/firebase_auth.dart` (NEW)
- `ServiceAccountCredentials` class — parses JSON key files
- `FirebaseAuth` class — JWT creation, RSA-SHA256 signing (via `pointycastle`), OAuth2 token exchange and caching
- `FirebaseAuth.fromConfig()` — resolves credentials from 3 sources:
  1. `credentials_file` in `build.yaml`
  2. `GOOGLE_APPLICATION_CREDENTIALS` env var
  3. `.firebase-credentials.json` in project root

## Files Modified

### `lib/src/uploader/firebase_uploader.dart` (REWRITTEN)
- Replaced all Firebase CLI calls with REST API
- Now requires `FirebaseAuth` instance in constructor
- Upload flow: `_uploadBinary()` → `_updateReleaseNotes()` → `_distribute()`
- API endpoints:
  - Upload: `POST .../upload/v1/projects/{project_number}/apps/{app_id}/releases:upload`
  - Release notes: `PATCH .../v1/{release_name}?updateMask=releaseNotes.text`
  - Distribute: `POST .../v1/{release_name}:distribute`
- `_pollOperation()` handles long-running uploads with exponential backoff (2s → 10s cap)
- `UploadOptions` now takes `projectNumber` instead of `projectId`, no longer has `token` field

### `lib/src/commands/deploy_command.dart`
- `_uploadToFirebase()` rewritten to use `FirebaseAuth.fromConfig()` and new `FirebaseUploader`
- Now passes `projectNumber` and `credentialsFile`
- Auto-gitignores `.firebase-credentials.json`
- Closes `FirebaseAuth` in finally block
- Updated error messages: removed Firebase CLI references, added service account guidance

### `lib/src/parser/build_config.dart`
- Added `credentialsFile` field to `FirebaseConfigInfo`
- Updated `fromMap` factory to parse `credentials_file` from YAML

### `lib/src/templates/build_yaml_template.dart`
- Updated auth comment block for service account credentials
- Added `credentials_file` line to generated firebase section

### `pubspec.yaml`
- Added dependencies: `http: ^1.2.0`, `pointycastle: ^3.9.1`
- `process_run` kept (still used by FlutterBuilder and GitHelper)

### `lib/pipo_firebase_app_distribution.dart`
- Added export: `export 'src/auth/firebase_auth.dart'`

### `bin/pipo_firebase_app_distribution.dart`
- Updated help text: service account credentials instead of Firebase CLI

### `README.md`
- Replaced "Smart Authentication" with "Service Account Authentication"
- Updated prerequisites: removed Firebase CLI, added service account setup
- Added `credentials_file` to build.yaml example
- Rewrote "Firebase Authentication" section (setup, credentials resolution, Jenkins CI/CD, security notes)
- Updated project structure: `.firebase-credentials.json` instead of `.firebase-token`
- Updated troubleshooting for service account errors

### `CLAUDE.md`
- Updated architecture docs to reflect REST API changes

## Technical Details

### RSA-SHA256 Signing
- Uses `pointycastle` library
- `RSASigner(Digest('SHA-256'), '0609608648016503040201')`
- PEM parsing: strips headers → base64 decode → PKCS#8 ASN1 parse → extract RSA key components (modulus, privateExponent, p, q)

### JWT Flow
1. Create JWT with `iss` (client_email), `scope` (firebase.platform), `aud` (token_uri), `iat`, `exp`
2. Sign with RSA-SHA256 using service account private key
3. Exchange JWT for access token via `POST https://oauth2.googleapis.com/token`
4. Cache token until expiry (with 5-min buffer)

## Errors Encountered & Fixed

1. **Wrong pointycastle imports**: Used specific imports instead of barrel `pointycastle.dart`
2. **`SHA256Digest()` not valid**: Changed to `Digest('SHA-256')` factory
3. **`ASN1OctetString.valueBytes` incorrect**: Uses `octets` property
4. **Unnecessary RSASignature cast**: Removed (return type already correct)
5. **Missing `dart:io` import**: Added back for `Directory` and `Platform`

## Final Status

- All 11 tasks completed
- `dart analyze` — No issues found
- Ready for testing with real service account and publishing to pub.dev
