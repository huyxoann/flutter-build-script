# Flutter Build & Distribute Script

A portable CLI tool to automate Flutter release builds **and distribute** them to Firebase App Distribution, Google Play Store, and App Store (TestFlight) via Fastlane.

Supports **macOS**, **Linux**, and **Windows**.

## ✨ Features

- **Cross-Platform**: Works on macOS/Linux (Bash) and Windows (PowerShell)
- **Portable & Reusable**: Derives the app name from the project folder — drop-in ready for any Flutter project
- **Automated Build Numbering**: Git commit count (`git rev-list --count HEAD`) for unique, increasing build numbers
- **Dynamic Versioning**: Extracts `version` from `pubspec.yaml` automatically
- **Pre-flight Safety Check**: Warns on uncommitted changes before release builds
- **Clean Build Lifecycle**: `flutter clean` + `flutter pub get` before every build
- **Multi-Target Build**: Android App Bundle (`.aab`), APK (`.apk`), iOS Archive (`.ipa`)
- **Standardized Output**: Timestamped filenames in `build/dist/`
- **Optional Obfuscation**: `--obfuscate` for Dart symbol obfuscation
- **Distribution via Fastlane**: Ship to Firebase, Google Play, and TestFlight in one command
- **Auto-Bootstrap Fastlane**: Temp config generated on the fly — no files added to your project
- **Multi-Target Distribution**: e.g., `--distribute firebase,appstore` in one run
- **Slack Notifications**: Post a Block Kit summary to Slack automatically after distribution
- **Distribute-Only Mode**: Re-upload existing artifacts without rebuilding
- **Dry-Run Mode**: Validate everything without uploading

---

## 📦 Installation

### One-Liner (Recommended)

#### Option 1: Public Repository
If the repository is public:

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.ps1 | iex
```

#### Option 2: Private Repository (via GitHub CLI `gh`)
If the repository is private (or to resolve `curl: (56) 404 Not Found`), authenticate with GitHub CLI:

**macOS / Linux:**
```bash
curl -fsSL -H "Authorization: token $(gh auth token)" https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.sh | bash
```

**Windows (PowerShell):**
```powershell
$token = (gh auth token).Trim(); irm https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.ps1 -Headers @{ Authorization = "token $token" } | iex
```


This clones the repo to `~/.build_script`, installs dependencies (Fastlane, Ruby, Bundler), and adds `build_release` to your PATH.

### Manual Install (Alternative)

```bash
git clone https://github.com/inhvn/flutter-build-script.git ~/.build_script
~/.build_script/install.sh          # macOS/Linux
# or
~/.build_script/install.ps1         # Windows
```

### Per-Project Install

Copy the script directly into a Flutter project:

```bash
mkdir -p scripts
cp ~/.build_script/scripts/build_release.sh scripts/    # macOS/Linux
chmod +x scripts/build_release.sh
```

### Uninstall

```bash
~/.build_script/install.sh --uninstall     # macOS/Linux
~/.build_script/install.ps1 --uninstall    # Windows
```

### Prerequisites

The installer handles these automatically. If you need to install manually:

| Dependency | macOS/Linux | Windows |
| :--- | :--- | :--- |
| Ruby | `brew install ruby` | `choco install ruby` |
| Fastlane | `brew install fastlane` | `gem install fastlane` |
| Bundler | Included with Fastlane | `gem install bundler` |

> **macOS/Linux**: Homebrew (`brew`) is required. Install from [brew.sh](https://brew.sh) if needed.

---

## ⚙️ Configuration & Project Setup

### Quick Setup (Recommended)

In your Flutter project root, run:

```bash
build_release --setup
```

This will:
1. ✅ Create `.build_release.env` (and add it to `.gitignore`)
2. 🔍 **Auto-detect Firebase App IDs** from `firebase.json` or `google-services.json` / `GoogleService-Info.plist`
3. 🔍 **Auto-detect Firebase tester groups** via `firebase appdistribution:groups:list`
4. 🔍 **Auto-detect Google Play JSON key** from `~/.config/gplay/service-account.json`
5. 🔍 **Auto-detect App Store Connect key** from `~/.config/appstore/AuthKey_*.p8` (and auto-extract Key ID)
6. 🔍 **Auto-detect Slack Webhook URL** from `~/.config/slack/webhook_url`

### Machine Credential Directories

The installer creates these standard directories on your machine:
* `~/.config/gplay/` — Put your Google Play `service-account.json` here (shared across all projects)
* `~/.config/appstore/` — Put your App Store Connect `AuthKey_<KEY_ID>.p8` here
* `~/.config/slack/` — Put `webhook_url` (or `bot_token` + `channel_id`) here for shared Slack notifications

When you run `build_release --setup` in any project, it automatically links to these keys!

> **⚠️ Important**: Never commit `.build_release.env` or credential files to Git!

---

## 🚀 Usage & Examples

### Build Only (No Distribution)

```bash
build_release                         # Android App Bundle (.aab) — default
build_release apk                     # Android APK
build_release ipa                     # iOS IPA (macOS only)
build_release apk --debug             # Debug APK
build_release appbundle --obfuscate   # With Dart obfuscation
```

### Build & Distribute

```bash
# Firebase App Distribution — Android
build_release --distribute firebase --platform android

# Firebase — iOS with custom groups and notes
build_release --distribute firebase --platform ios \
  --groups "QA,PM" --notes "Bug fix release v1.2"

# Google Play Store — internal track (default)
build_release --distribute playstore

# Google Play Store — beta track
build_release --distribute playstore --track beta

# App Store / TestFlight (macOS only)
build_release --distribute appstore

# Multi-target: Firebase + TestFlight (both use IPA)
build_release --distribute firebase,appstore --platform ios

# Dry-run — validate everything, skip upload
build_release --distribute playstore --dry-run
```

### Distribute-Only (Skip Build)

Re-upload the latest artifact from `build/dist/` without rebuilding:

```bash
build_release --distribute firebase --platform android --distribute-only
build_release --distribute appstore --distribute-only
```

---

## 📋 Command Line Options

### Build Options

| Argument | Category | Description | Default |
| :--- | :--- | :--- | :--- |
| `appbundle` | Target | Android App Bundle (`.aab`) | ✅ Yes |
| `apk` | Target | Android APK (`.apk`) | ❌ No |
| `ipa` | Target | iOS IPA (`.ipa`) — macOS only | ❌ No |
| `release`, `--release` | Mode | Release build | ✅ Yes |
| `profile`, `--profile` | Mode | Profile build | ❌ No |
| `debug`, `--debug` | Mode | Debug build | ❌ No |
| `--obfuscate` | Flag | Dart obfuscation & debug symbol export | ❌ No |
| `--build-number <num>`, `-b <num>` | Option | Explicit build number (overrides auto-detection) | _(none)_ |
| `--skip-store-version` | Flag | Skip querying Google Play / App Store for latest build number | ❌ No |

### Distribution Options

| Argument | Description | Default |
| :--- | :--- | :--- |
| `--distribute <targets>` | Comma-separated: `firebase`, `playstore`, `appstore` | _(none)_ |
| `--platform <android\|ios>` | Required for `firebase` | _(none)_ |
| `--track <track>` | Play Store track: `internal`, `alpha`, `beta`, `production` | `internal` |
| `--package-name <pkg>` | Android package name (auto-detected from `build.gradle` if omitted) | _(auto)_ |
| `--groups <groups>` | Firebase tester groups (comma-separated) | from `.build_release.env` |
| `--notes <text>` | Firebase release notes | from `.build_release.env` |
| `--distribute-only` | Skip build, use latest artifact | ❌ No |
| `--dry-run` | Validate and build, skip upload | ❌ No |
| `--slack-webhook <url>` | Slack Incoming Webhook URL (overrides `.build_release.env`) | from `.build_release.env` |
| `--slack-channel <id>` | Slack Channel ID when using `SLACK_BOT_TOKEN` | from `.build_release.env` |
| `--slack-mention <text>` | Mention in Slack (`here`, `channel`, `<@U123>`, `<!subteam^ID>`) | from `.build_release.env` |
| `--no-slack` | Skip Slack notification for this run | ❌ No |

### Build Target Auto-Inference

When `--distribute` is used without an explicit target:

| `--distribute` | `--platform` | Inferred Target |
| :--- | :--- | :--- |
| `firebase` | `android` | `apk` |
| `firebase` | `ios` | `ipa` |
| `playstore` | _(implied)_ | `appbundle` |
| `appstore` | _(implied)_ | `ipa` |

> **Note**: Multi-target only works when all targets share the same artifact type. `firebase,appstore` (both IPA) ✅ — `firebase,playstore` on Android (APK vs AAB) ❌

### Platform Support

| Feature | macOS/Linux | Windows |
| :--- | :--- | :--- |
| Build `apk` / `appbundle` | ✅ | ✅ |
| Build `ipa` | ✅ | ❌ |
| Distribute `firebase` (Android) | ✅ | ✅ |
| Distribute `firebase` (iOS) | ✅ | ❌ |
| Distribute `playstore` | ✅ | ✅ |
| Distribute `appstore` | ✅ | ❌ |

---

## 📂 Output Structure

```text
build/dist/
├── <app_name>_v0.1.0_b124_20260825_1030.aab          # Release artifact
├── <app_name>_debug_v0.1.0_b124_20260825_1035.apk    # Debug artifact
├── <app_name>_v0.1.0_b124_20260825_1040.ipa           # iOS artifact (macOS only)
├── symbols/                                            # (--obfuscate only)
│   └── symbols_v0.1.0_b124_20260825_1030/
└── .fastlane/                                          # Auto-generated, cleaned by flutter clean
    ├── Gemfile
    ├── vendor/
    └── fastlane/
        ├── Fastfile
        └── Pluginfile
```

Running `flutter clean` wipes everything in `build/`, including artifacts and Fastlane cache.

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

### App Store Connect (TestFlight) — macOS only

1. Go to [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Integrations → App Store Connect API
2. Generate a new API Key with **App Manager** role
3. Download the `.p8` key file (⚠️ can only be downloaded once!)
4. Add to `.build_release.env`:
   ```env
   ASC_KEY_ID=ABC123
   ASC_ISSUER_ID=def-456-ghi
   ASC_KEY_FILE=~/.config/appstore/AuthKey_ABC123.p8
   ```

### Slack Notification (Optional)

Supports either **Incoming Webhook URL** or **Slack Bot Token + Channel ID**:

```env
# Option 1: Incoming Webhook URL (or save globally in ~/.config/slack/webhook_url)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T000/B000/XXXX

# Option 2: Slack Bot Token + Channel ID (or save globally in ~/.config/slack/bot_token & channel_id)
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0BQ89RRCKV

# Optional mention
SLACK_MENTION=here
```

---

## 💡 Tips

### CI/CD Integration

- Fetch full Git history (`fetch-depth: 0`) for accurate build numbering.
- Set credentials as environment variables instead of `.build_release.env`.

### iOS Signing

The script relies on Xcode automatic signing by default. For a specific export method (e.g., ad-hoc for Firebase), set in `.build_release.env`:

```env
IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.plist
```

### First Run Performance

The first `--distribute` run installs Fastlane gems locally in `build/dist/.fastlane/vendor/`. Subsequent runs reuse the cache (until `flutter clean`).

### Updating

```bash
cd ~/.build_script && git pull    # macOS/Linux

# or re-run the one-liner (Public Repo):
curl -fsSL https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.sh | bash

# or re-run with GitHub CLI auth (Private Repo):
curl -fsSL -H "Authorization: token $(gh auth token)" https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.sh | bash
```

```powershell
# Windows (Public Repo)
irm https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.ps1 | iex

# Windows (Private Repo via gh)
$token = (gh auth token).Trim(); irm https://raw.githubusercontent.com/inhvn/flutter-build-script/main/setup.ps1 -Headers @{ Authorization = "token $token" } | iex
```
