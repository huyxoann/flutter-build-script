# Flutter Build & Distribute Script

A standardized Bash script to automate Flutter release builds **and distribute** them to Firebase App Distribution, Google Play Store, and App Store (TestFlight) via Fastlane.

## ✨ Features

- **Portable & Reusable**: Automatically derives the app name from the project's root folder name—no hardcoded values, drop-in ready for any Flutter project.
- **Automated Build Numbering**: Uses Git commit count (`git rev-list --count HEAD`) for unique, strictly increasing build numbers.
- **Dynamic Semantic Versioning**: Automatically extracts `version` from `pubspec.yaml`.
- **Pre-flight Safety Check**: Warns and prompts if the Git working tree has uncommitted changes before release builds.
- **Clean Build Lifecycle**: Purges stale artifacts and re-fetches packages automatically.
- **Multi-Target Build**: Supports Android App Bundle (`.aab`), APK (`.apk`), and iOS Archive (`.ipa`).
- **Standardized Artifact Output**: Timestamped filenames in `build/dist/`.
- **Optional Obfuscation**: `--obfuscate` for Dart symbol obfuscation with debug symbol export.
- **🆕 Distribution via Fastlane**: Ship to Firebase App Distribution, Google Play, and TestFlight in one command.
- **🆕 Auto-Bootstrap**: Fastlane config is generated as temp files—no permanent files added to your project.
- **🆕 Multi-Target Distribution**: Distribute to multiple targets in one run (e.g., `firebase,appstore`).
- **🆕 Distribute-Only Mode**: Re-upload existing artifacts without rebuilding.
- **🆕 Dry-Run Mode**: Validate config and build without uploading.

---

## 📦 Installation & Setup

### Step 1: Copy the Script

Place `build_release.sh` inside a `scripts/` directory at your Flutter project root:

```bash
mkdir -p scripts
cp /path/to/build_script/scripts/build_release.sh scripts/
chmod +x scripts/build_release.sh
```

### Step 2: Configure Distribution (Optional)

If you want to use distribution features, create `.build_release.env` at the project root:

```bash
cp /path/to/build_script/.build_release.env.example .build_release.env
```

Edit `.build_release.env` with your project's credentials:

```env
# Firebase
FIREBASE_APP_ID_ANDROID=1:123456789:android:abcdef
FIREBASE_APP_ID_IOS=1:123456789:ios:abcdef
FIREBASE_CLI_TOKEN=your_token_here
FIREBASE_TESTER_GROUPS=QA,Dev

# Google Play
GOOGLE_PLAY_JSON_KEY=~/.config/gplay/service-account.json

# App Store Connect
ASC_KEY_ID=ABC123
ASC_ISSUER_ID=def-456-ghi
ASC_KEY_FILE=~/.config/appstore/AuthKey_ABC123.p8
```

> **⚠️ Important**: Add `.build_release.env` to your `.gitignore` — it contains secrets!

### Step 3: Install Distribution Dependencies

Only needed if using `--distribute`:

```bash
# Ruby (usually pre-installed on macOS)
ruby --version

# Bundler
gem install bundler

# Fastlane
gem install fastlane
# or: brew install fastlane
```

### Step 4: Verify

```bash
./scripts/build_release.sh --help
```

---

## 🚀 Usage & Examples

### Build Only (No Distribution)

```bash
# Build Android App Bundle (.aab) — default
./scripts/build_release.sh

# Build Android APK
./scripts/build_release.sh apk

# Build iOS IPA
./scripts/build_release.sh ipa

# Debug APK for local testing
./scripts/build_release.sh apk --debug

# Build with obfuscation
./scripts/build_release.sh appbundle --obfuscate
```

### Build & Distribute

```bash
# Firebase App Distribution — Android
./scripts/build_release.sh --distribute firebase --platform android

# Firebase App Distribution — iOS with custom groups and notes
./scripts/build_release.sh --distribute firebase --platform ios \
  --groups "QA,PM" --notes "Bug fix release v1.2"

# Google Play Store — internal track (default)
./scripts/build_release.sh --distribute playstore

# Google Play Store — beta track
./scripts/build_release.sh --distribute playstore --track beta

# App Store (TestFlight)
./scripts/build_release.sh --distribute appstore

# Multi-target: Firebase + TestFlight (both use IPA)
./scripts/build_release.sh --distribute firebase,appstore --platform ios

# Dry-run — validate everything, skip upload
./scripts/build_release.sh --distribute playstore --dry-run
```

### Distribute-Only (Skip Build)

Re-upload the latest artifact from `build/dist/` without rebuilding:

```bash
# Re-distribute latest APK to Firebase
./scripts/build_release.sh --distribute firebase --platform android --distribute-only

# Re-distribute latest IPA to TestFlight
./scripts/build_release.sh --distribute appstore --distribute-only
```

---

## 📋 Command Line Options

### Build Options

| Argument | Category | Description | Default |
| :--- | :--- | :--- | :--- |
| `appbundle` | Target | Builds Android App Bundle (`.aab`) | ✅ Yes |
| `apk` | Target | Builds Android APK (`.apk`) | ❌ No |
| `ipa` | Target | Builds iOS IPA (`.ipa`) | ❌ No |
| `release`, `--release` | Mode | Release build | ✅ Yes |
| `profile`, `--profile` | Mode | Profile build for performance analysis | ❌ No |
| `debug`, `--debug` | Mode | Debug build | ❌ No |
| `--obfuscate` | Flag | Enables Dart obfuscation & debug symbol export | ❌ No |

### Distribution Options

| Argument | Description | Default |
| :--- | :--- | :--- |
| `--distribute <targets>` | Comma-separated: `firebase`, `playstore`, `appstore` | _(none)_ |
| `--platform <android\|ios>` | Required for `firebase` | _(none)_ |
| `--track <track>` | Play Store track: `internal`, `alpha`, `beta`, `production` | `internal` |
| `--groups <groups>` | Firebase tester groups (comma-separated) | from `.build_release.env` |
| `--notes <text>` | Firebase release notes | from `.build_release.env` |
| `--distribute-only` | Skip build, use latest artifact from `build/dist/` | ❌ No |
| `--dry-run` | Validate and build, but skip actual upload | ❌ No |

### Build Target Auto-Inference

When `--distribute` is used without an explicit target, the build target is inferred:

| `--distribute` | `--platform` | Inferred Target |
| :--- | :--- | :--- |
| `firebase` | `android` | `apk` |
| `firebase` | `ios` | `ipa` |
| `playstore` | _(implied)_ | `appbundle` |
| `appstore` | _(implied)_ | `ipa` |

> **Note**: Multi-target distribution only works when all targets use the same artifact type. For example, `firebase,appstore` (both IPA) works, but `firebase,playstore` on Android (APK vs AAB) does not.

---

## 📂 Output Structure

```text
build/dist/
├── <app_name>_v0.1.0_b124_20260825_1030.aab          # Release artifact
├── <app_name>_debug_v0.1.0_b124_20260825_1035.apk    # Debug artifact
├── <app_name>_v0.1.0_b124_20260825_1040.ipa           # iOS artifact
├── symbols/                                            # (--obfuscate only)
│   └── symbols_v0.1.0_b124_20260825_1030/
└── .fastlane/                                          # Auto-generated, cleaned by flutter clean
    ├── Gemfile
    ├── vendor/
    └── fastlane/
        ├── Fastfile
        └── Pluginfile
```

### 🧹 Automatic Cleanup

Running `flutter clean` wipes the entire `build/` directory, including release artifacts, Fastlane temp files, and cached gems.

---

## 🔐 Credentials Setup

### Firebase App Distribution

1. Go to [Firebase Console](https://console.firebase.google.com/) → Project Settings → General
2. Copy the **App ID** for your Android/iOS app
3. Generate a CLI token:
   ```bash
   firebase login:ci
   ```
4. Add to `.build_release.env`:
   ```env
   FIREBASE_APP_ID_ANDROID=1:123456789:android:abcdef
   FIREBASE_CLI_TOKEN=your_token_here
   ```

### Google Play Store

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → IAM → Service Accounts
2. Create a service account with **Editor** role
3. Download the JSON key file
4. In [Google Play Console](https://play.google.com/console) → Settings → API access, link the service account
5. Add to `.build_release.env`:
   ```env
   GOOGLE_PLAY_JSON_KEY=~/.config/gplay/service-account.json
   ```

### App Store Connect (TestFlight)

1. Go to [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Integrations → App Store Connect API
2. Generate a new API Key with **App Manager** role
3. Download the `.p8` key file (⚠️ can only be downloaded once!)
4. Add to `.build_release.env`:
   ```env
   ASC_KEY_ID=ABC123
   ASC_ISSUER_ID=def-456-ghi
   ASC_KEY_FILE=~/.config/appstore/AuthKey_ABC123.p8
   ```

---

## 💡 Tips

### CI/CD Integration

- Ensure your checkout step fetches the full Git history (`fetch-depth: 0`) for accurate build numbering.
- In CI, set credentials as environment variables instead of `.build_release.env`.

### iOS Signing

The script relies on Xcode automatic signing by default. If you need a specific export method (e.g., ad-hoc for Firebase), set `IOS_EXPORT_OPTIONS_PLIST` in `.build_release.env`:

```env
IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.plist
```

### First Run Performance

The first `--distribute` run installs Fastlane gems locally in `build/dist/.fastlane/vendor/`. Subsequent runs reuse the cache (until `flutter clean` is run).
