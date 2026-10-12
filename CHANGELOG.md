# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-12

### Added
- **Store-Driven Build Number Auto-Resolution**:
  - **Google Play Console (Android)**: Automatically queries all track version codes via Fastlane and sets the build number to `(max_track_version_code + 1)`.
  - **App Store Connect / TestFlight (iOS)**: Automatically queries the latest TestFlight build number via Fastlane and sets the build number to `(latest_testflight_build_number + 1)`.
  - **Smart Fallback**: Gracefully falls back to `max(pubspec.yaml build number, git commit count)` if store credentials are not configured or network queries fail.
- **New CLI Options**:
  - `--build-number <num>` / `-b <num>`: Manually specify an exact build number, overriding auto-detection logic (supported in Bash & PowerShell).
  - `--skip-store-version`: Bypass querying Google Play / App Store and use local fallback resolution immediately.
- **iOS Signing & Export Options Auto-Detection**: Auto-detects `ExportOptions.plist` for IPA builds.
- **Installation & Setup for Public vs Private Repositories**:
  - **Public Repository (Option 1)**: Standard unauthenticated one-liner installer (`curl` on macOS/Linux, `irm` on Windows). Command to make repo public: `gh repo edit inhvn/flutter-build-script --visibility public`.
  - **Private Repository via GitHub CLI (Option 2)**: Authenticated one-liner installer using `gh auth token` (`curl -fsSL -H "Authorization: token $(gh auth token)" ...`) to avoid HTTP 404 errors on private GitHub repos.

### Changed
- `setup.sh`: Automatically discards dirty/uncommitted state in `~/.build_script` before pulling updates (`git reset --hard HEAD`).

---

## [1.0.0] - 2026-09-24

### Added
- **Cross-Platform Support**: Added Windows PowerShell scripts (`build_release.ps1`, `install.ps1`, `setup.ps1`).
- **Remote Installer One-Liner**: `setup.sh` (macOS/Linux) and `setup.ps1` (Windows) for single-command installation and update.
- **Fastlane Distribution Support**: Build and distribute to Firebase App Distribution, Google Play Store, and App Store TestFlight in one command.
- **Interactive Project Setup (`--setup`)**:
  - Generates `.build_release.env` template and configures `.gitignore`.
  - Auto-detects Android package name from `build.gradle` or manifest.
  - Auto-detects keystore file located in `android/app/` or `android/`.
  - Auto-detects Firebase App IDs from `firebase.json` or config plists/json.
  - Auto-detects Firebase tester groups.
  - Auto-creates `~/.config/gplay` and `~/.config/appstore` and detects API keys.
- **Pre-flight Safety Checks**: Android keystore existence & passwords validation, uncommitted git changes warning.
- **Clean Build Lifecycle**: Automated `flutter clean` + `flutter pub get`, dynamic versioning from `pubspec.yaml`, and git commit count build numbering.
