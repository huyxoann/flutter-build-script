#!/bin/bash
set -e

# ==========================================
# FLUTTER BUILD & DISTRIBUTE SCRIPT
# ==========================================
# Builds Flutter artifacts (APK, AAB, IPA) and optionally distributes
# them to Firebase App Distribution, Google Play Store, or App Store
# (TestFlight) via Fastlane.
#
# Run with --help for usage.

# Resolve project root: if script lives in <project>/scripts/, use that.
# Otherwise (global install / symlink), use the current working directory.
_SCRIPT_PARENT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$_SCRIPT_PARENT/pubspec.yaml" ]; then
  PROJECT_ROOT="$_SCRIPT_PARENT"
else
  PROJECT_ROOT="$(pwd)"
fi
unset _SCRIPT_PARENT

if [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
  echo "❌ No pubspec.yaml found in $PROJECT_ROOT"
  echo "   Run this command from the root of a Flutter project."
  exit 1
fi
cd "$PROJECT_ROOT"

APP_NAME="$(basename "$PROJECT_ROOT")"
BUILD_DIR="build/dist"
SYMBOLS_DIR="$BUILD_DIR/symbols"
FASTLANE_WORK_DIR="$BUILD_DIR/.fastlane"

# ==========================================
# DEFAULTS
# ==========================================
TARGET=""
BUILD_MODE="release"
ENABLE_OBFUSCATE=false
DISTRIBUTE_TARGETS=""
PLATFORM=""
PLAY_TRACK="internal"
DIST_GROUPS=""
DIST_NOTES=""
DISTRIBUTE_ONLY=false
DRY_RUN=false

# Config defaults (overridden by .build_release.env)
FIREBASE_APP_ID_ANDROID=""
FIREBASE_APP_ID_IOS=""
FIREBASE_CLI_TOKEN=""
FIREBASE_TESTER_GROUPS="testers"
FIREBASE_RELEASE_NOTES=""
GOOGLE_PLAY_JSON_KEY=""
ANDROID_PACKAGE_NAME=""
ASC_KEY_ID=""
ASC_ISSUER_ID=""
ASC_KEY_FILE=""
IOS_EXPORT_OPTIONS_PLIST=""

# ==========================================
# LOAD PROJECT CONFIG
# ==========================================
if [ -f ".build_release.env" ]; then
  # shellcheck disable=SC1091
  source ".build_release.env"
fi

# ==========================================
# HELP
# ==========================================
show_help() {
  cat << 'EOF'
Usage: build_release.sh [TARGET] [MODE] [OPTIONS]

Targets:
  appbundle                Build Android App Bundle (.aab) [Default]
  apk                      Build Android APK (.apk)
  ipa                      Build iOS IPA (.ipa)

Build Modes:
  release, --release       Build release version [Default]
  profile, --profile       Build profile version (for performance profiling)
  debug,   --debug         Build debug version

Distribution:
  --distribute <targets>   Comma-separated: firebase, playstore, appstore
  --platform <os>          android or ios (required for firebase)
  --track <track>          Google Play track: internal, alpha, beta, production [Default: internal]
  --package-name <pkg>     Android package name (auto-detected if omitted)
  --groups <groups>        Firebase tester groups, comma-separated
  --notes <text>           Release notes for Firebase distribution
  --distribute-only        Skip build, distribute latest artifact from build/dist/
  --dry-run                Validate config and build, but skip actual upload

Options:
  --setup                  Initialize .build_release.env and .gitignore in current project
  --obfuscate              Enable Dart symbol obfuscation (release/profile only)
  --help, -h               Show this help message

Examples:
  # Build Android App Bundle (default, no distribution)
  build_release.sh

  # Build & distribute APK to Firebase
  build_release.sh --distribute firebase --platform android

  # Build & distribute IPA to Firebase with groups and notes
  build_release.sh --distribute firebase --platform ios --groups "QA,PM" --notes "Bug fix v1.2"

  # Build & upload AAB to Google Play (internal track)
  build_release.sh --distribute playstore

  # Build & upload AAB to Google Play beta track
  build_release.sh --distribute playstore --track beta

  # Build & upload IPA to TestFlight
  build_release.sh --distribute appstore

  # Multi-target: Firebase + TestFlight (both use IPA)
  build_release.sh --distribute firebase,appstore --platform ios

  # Re-distribute existing artifact (skip build)
  build_release.sh --distribute firebase --platform android --distribute-only

  # Dry-run (validate everything, skip actual upload)
  build_release.sh --distribute playstore --dry-run

Config:
  Create .build_release.env at your project root (see .build_release.env.example).
  Add .build_release.env to .gitignore — it contains secrets.
EOF
  exit 0
}

# ==========================================
# PROJECT SETUP
# ==========================================
run_setup() {
  echo "⚙️  Setting up project for build_release..."
  echo ""

  # --- .build_release.env ---
  if [ -f ".build_release.env" ]; then
    echo "⚠️  .build_release.env already exists."
    if [ -t 0 ]; then
      read -p "Overwrite? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Skipped .build_release.env"
      else
        create_env_file
      fi
    else
      echo "   Skipped (non-interactive)."
    fi
  else
    create_env_file
  fi

  # --- .gitignore ---
  if [ -f ".gitignore" ]; then
    if ! grep -qxF '.build_release.env' .gitignore; then
      echo "" >> .gitignore
      echo "# Build release config (contains secrets)" >> .gitignore
      echo ".build_release.env" >> .gitignore
      echo "✅ Added .build_release.env to .gitignore"
    else
      echo "ℹ️  .build_release.env already in .gitignore"
    fi
  else
    echo "# Build release config (contains secrets)" > .gitignore
    echo ".build_release.env" >> .gitignore
    echo "✅ Created .gitignore with .build_release.env"
  fi

  echo ""
  echo "🚀 Setup complete! Next steps:"
  echo "   1. Edit .build_release.env with your credentials"
  echo "   2. Run: build_release --distribute firebase --platform android"
  exit 0
}

detect_firebase_ids() {
  _DETECTED_ANDROID_ID=""
  _DETECTED_IOS_ID=""
  _DETECTED_PROJECT_ID=""

  # 1. firebase.json (FlutterFire CLI)
  if [ -f "firebase.json" ] && command -v python3 &>/dev/null; then
    _DETECTED_ANDROID_ID=$(python3 -c "
import json
try:
    d = json.load(open('firebase.json'))
    print(d['flutter']['platforms']['android']['default']['appId'])
except: pass
" 2>/dev/null)
    _DETECTED_IOS_ID=$(python3 -c "
import json
try:
    d = json.load(open('firebase.json'))
    print(d['flutter']['platforms']['ios']['default']['appId'])
except: pass
" 2>/dev/null)
    _DETECTED_PROJECT_ID=$(python3 -c "
import json
try:
    d = json.load(open('firebase.json'))
    p = d['flutter']['platforms']
    print(p.get('android',{}).get('default',{}).get('projectId','') or p.get('ios',{}).get('default',{}).get('projectId',''))
except: pass
" 2>/dev/null)
  fi

  # 2. Fallback: google-services.json (Android)
  if [ -z "$_DETECTED_ANDROID_ID" ] && [ -f "android/app/google-services.json" ] && command -v python3 &>/dev/null; then
    _DETECTED_ANDROID_ID=$(python3 -c "
import json
try:
    d = json.load(open('android/app/google-services.json'))
    print(d['client'][0]['client_info']['mobilesdk_app_id'])
except: pass
" 2>/dev/null)
    if [ -z "$_DETECTED_PROJECT_ID" ]; then
      _DETECTED_PROJECT_ID=$(python3 -c "
import json
try:
    d = json.load(open('android/app/google-services.json'))
    print(d['project_info']['project_id'])
except: pass
" 2>/dev/null)
    fi
  fi

  # 3. Fallback: GoogleService-Info.plist (iOS)
  if [ -z "$_DETECTED_IOS_ID" ] && [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    _DETECTED_IOS_ID=$(/usr/libexec/PlistBuddy -c "Print :GOOGLE_APP_ID" "ios/Runner/GoogleService-Info.plist" 2>/dev/null || true)
  fi
}

detect_firebase_groups() {
  _DETECTED_TESTER_GROUPS=""

  # Requires firebase CLI + python3 + project ID
  if ! command -v firebase &>/dev/null || ! command -v python3 &>/dev/null || [ -z "$_DETECTED_PROJECT_ID" ]; then
    return
  fi

  local json_output
  json_output=$(firebase appdistribution:groups:list --project "$_DETECTED_PROJECT_ID" --json 2>/dev/null) || return

  _DETECTED_TESTER_GROUPS=$(python3 -c "
import json, sys
try:
    d = json.loads('''$json_output''')
    groups = [g['displayName'] for g in d.get('result',{}).get('groups',[])]
    print(','.join(groups))
except: pass
" 2>/dev/null)
}

detect_android_package_name() {
  _DETECTED_ANDROID_PACKAGE=""

  # 1. build.gradle.kts or build.gradle (applicationId has priority over namespace)
  local gradle_file
  for gradle_file in "android/app/build.gradle.kts" "android/app/build.gradle"; do
    if [ -f "$gradle_file" ]; then
      local pkg
      pkg=$(sed -n -E 's/^[[:space:]]*applicationId[[:space:]=]+["'"'"']([^"'"'"']+)["'"'"'].*/\1/p' "$gradle_file" | head -1)
      if [ -z "$pkg" ]; then
        pkg=$(sed -n -E 's/^[[:space:]]*namespace[[:space:]=]+["'"'"']([^"'"'"']+)["'"'"'].*/\1/p' "$gradle_file" | head -1)
      fi
      if [ -n "$pkg" ]; then
        _DETECTED_ANDROID_PACKAGE="$pkg"
        return
      fi
    fi
  done

  # 2. Fallback: google-services.json
  if [ -f "android/app/google-services.json" ] && command -v python3 &>/dev/null; then
    _DETECTED_ANDROID_PACKAGE=$(python3 -c "
import json
try:
    d = json.load(open('android/app/google-services.json'))
    print(d['client'][0]['client_info']['android_client_info']['package_name'])
except: pass
" 2>/dev/null)
    if [ -n "$_DETECTED_ANDROID_PACKAGE" ]; then
      return
    fi
  fi

  # 3. Fallback: AndroidManifest.xml
  if [ -f "android/app/src/main/AndroidManifest.xml" ]; then
    _DETECTED_ANDROID_PACKAGE=$(sed -n -E 's/.*package=["'"'"']([^"'"'"']+)["'"'"'].*/\1/p' "android/app/src/main/AndroidManifest.xml" | head -1)
  fi
}

detect_machine_credentials() {
  _DETECTED_GPLAY_KEY=""
  _DETECTED_ASC_KEY_FILE=""
  _DETECTED_ASC_KEY_ID=""

  local gplay_dir="$HOME/.config/gplay"
  local appstore_dir="$HOME/.config/appstore"

  # Ensure machine credential folders exist
  mkdir -p "$gplay_dir" "$appstore_dir"

  # 1. Google Play JSON key
  if [ -f "$gplay_dir/service-account.json" ]; then
    _DETECTED_GPLAY_KEY="~/.config/gplay/service-account.json"
  else
    local first_json
    first_json=$(find "$gplay_dir" -maxdepth 1 -name "*.json" 2>/dev/null | head -1)
    if [ -n "$first_json" ]; then
      _DETECTED_GPLAY_KEY="~/.config/gplay/$(basename "$first_json")"
    fi
  fi

  # 2. App Store Connect .p8 key
  local first_p8
  first_p8=$(find "$appstore_dir" -maxdepth 1 -name "*.p8" 2>/dev/null | head -1)
  if [ -n "$first_p8" ]; then
    local p8_name
    p8_name=$(basename "$first_p8")
    _DETECTED_ASC_KEY_FILE="~/.config/appstore/$p8_name"
    if [[ "$p8_name" =~ AuthKey_([A-Za-z0-9]+)\.p8 ]]; then
      _DETECTED_ASC_KEY_ID="${BASH_REMATCH[1]}"
    fi
  fi
}

create_env_file() {
  detect_firebase_ids
  detect_firebase_groups
  detect_machine_credentials
  detect_android_package_name

  local tester_groups="${_DETECTED_TESTER_GROUPS:-testers}"

  cat > ".build_release.env" << ENV_TEMPLATE
# ==========================================
# .build_release.env — Project Build & Distribution Config
# ==========================================
# ⚠️  Do NOT commit this file — it contains secrets!

# === Firebase App Distribution ===
# App IDs from Firebase Console > Project Settings > General > Your apps
FIREBASE_APP_ID_ANDROID=$_DETECTED_ANDROID_ID
FIREBASE_APP_ID_IOS=$_DETECTED_IOS_ID

# Firebase CLI token (generate with: firebase login:ci)
FIREBASE_CLI_TOKEN=

# Default tester groups (comma-separated, can override with --groups)
FIREBASE_TESTER_GROUPS=$tester_groups

# Default release notes (can override with --notes)
FIREBASE_RELEASE_NOTES=

# === Google Play Store ===
# Android Package Name / Application ID (auto-detected if blank)
ANDROID_PACKAGE_NAME=$_DETECTED_ANDROID_PACKAGE

# Path to service account JSON key file
# Create at: Google Cloud Console > IAM > Service Accounts
GOOGLE_PLAY_JSON_KEY=$_DETECTED_GPLAY_KEY

# === App Store Connect (API Key — macOS only) ===
# Create at: App Store Connect > Users and Access > Integrations
ASC_KEY_ID=$_DETECTED_ASC_KEY_ID
ASC_ISSUER_ID=
ASC_KEY_FILE=$_DETECTED_ASC_KEY_FILE

# === iOS Build (Optional) ===
# Path to ExportOptions.plist for manual signing (omit for Xcode automatic signing)
# IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.plist
ENV_TEMPLATE

  echo "✅ Created .build_release.env"
  if [ -n "$_DETECTED_ANDROID_ID" ] || [ -n "$_DETECTED_IOS_ID" ]; then
    echo "   🔍 Auto-detected Firebase App IDs:"
    [ -n "$_DETECTED_ANDROID_ID" ] && echo "      Android: $_DETECTED_ANDROID_ID"
    [ -n "$_DETECTED_IOS_ID" ]     && echo "      iOS:     $_DETECTED_IOS_ID"
  fi
  if [ -n "$_DETECTED_TESTER_GROUPS" ]; then
    echo "   🔍 Auto-detected tester groups: $_DETECTED_TESTER_GROUPS"
  fi
  if [ -n "$_DETECTED_ANDROID_PACKAGE" ]; then
    echo "   🔍 Auto-detected Android package name: $_DETECTED_ANDROID_PACKAGE"
  fi
  if [ -n "$_DETECTED_GPLAY_KEY" ]; then
    echo "   🔍 Auto-detected Google Play key: $_DETECTED_GPLAY_KEY"
  fi
  if [ -n "$_DETECTED_ASC_KEY_FILE" ]; then
    echo "   🔍 Auto-detected App Store key: $_DETECTED_ASC_KEY_FILE"
    [ -n "$_DETECTED_ASC_KEY_ID" ] && echo "      Key ID: $_DETECTED_ASC_KEY_ID"
  fi
}

# ==========================================
# PARSE ARGUMENTS
# ==========================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    appbundle|apk|ipa)
      TARGET="$1"; shift ;;
    release|--release)
      BUILD_MODE="release"; shift ;;
    profile|--profile)
      BUILD_MODE="profile"; shift ;;
    debug|--debug)
      BUILD_MODE="debug"; shift ;;
    --obfuscate)
      ENABLE_OBFUSCATE=true; shift ;;
    --distribute)
      DISTRIBUTE_TARGETS="$2"; shift 2 ;;
    --distribute=*)
      DISTRIBUTE_TARGETS="${1#*=}"; shift ;;
    --platform)
      PLATFORM="$2"; shift 2 ;;
    --platform=*)
      PLATFORM="${1#*=}"; shift ;;
    --track)
      PLAY_TRACK="$2"; shift 2 ;;
    --track=*)
      PLAY_TRACK="${1#*=}"; shift ;;
    --package-name)
      ANDROID_PACKAGE_NAME="$2"; shift 2 ;;
    --package-name=*)
      ANDROID_PACKAGE_NAME="${1#*=}"; shift ;;
    --groups)
      DIST_GROUPS="$2"; shift 2 ;;
    --groups=*)
      DIST_GROUPS="${1#*=}"; shift ;;
    --notes)
      DIST_NOTES="$2"; shift 2 ;;
    --notes=*)
      DIST_NOTES="${1#*=}"; shift ;;
    --distribute-only)
      DISTRIBUTE_ONLY=true; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --setup)
      run_setup ;;
    --help|-h)
      show_help ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "Run '$0 --help' for usage."
      exit 1 ;;
  esac
done

# Apply defaults from config (CLI flags take priority)
DIST_GROUPS="${DIST_GROUPS:-$FIREBASE_TESTER_GROUPS}"
DIST_NOTES="${DIST_NOTES:-$FIREBASE_RELEASE_NOTES}"

# Auto-detect Android package name if not explicitly set
if [ -z "$ANDROID_PACKAGE_NAME" ]; then
  detect_android_package_name
  ANDROID_PACKAGE_NAME="$_DETECTED_ANDROID_PACKAGE"
fi

# ==========================================
# VALIDATE DISTRIBUTE TARGETS & INFER BUILD TARGET
# ==========================================
HAS_DISTRIBUTE=false
DIST_FIREBASE=false
DIST_PLAYSTORE=false
DIST_APPSTORE=false

if [ -n "$DISTRIBUTE_TARGETS" ]; then
  HAS_DISTRIBUTE=true
  IFS=',' read -ra DIST_ARRAY <<< "$DISTRIBUTE_TARGETS"
  for dist in "${DIST_ARRAY[@]}"; do
    case "$dist" in
      firebase)   DIST_FIREBASE=true ;;
      playstore)  DIST_PLAYSTORE=true ;;
      appstore)   DIST_APPSTORE=true ;;
      *)
        echo "❌ Unknown distribute target: $dist"
        echo "   Valid targets: firebase, playstore, appstore"
        exit 1 ;;
    esac
  done
fi

if [ "$DISTRIBUTE_ONLY" = true ] && [ "$HAS_DISTRIBUTE" = false ]; then
  echo "❌ --distribute-only requires --distribute <targets>."
  exit 1
fi

# Validate --platform value
if [ -n "$PLATFORM" ] && [[ "$PLATFORM" != "android" && "$PLATFORM" != "ios" ]]; then
  echo "❌ Invalid platform: $PLATFORM"
  echo "   Valid values: android, ios"
  exit 1
fi

# Auto-infer build target from distribute targets
if [ "$HAS_DISTRIBUTE" = true ] && [ -z "$TARGET" ]; then
  INFERRED_TARGET=""

  if [ "$DIST_FIREBASE" = true ]; then
    if [ -z "$PLATFORM" ]; then
      echo "❌ --platform android|ios is required when distributing to firebase."
      exit 1
    fi
    case "$PLATFORM" in
      android) INFERRED_TARGET="apk" ;;
      ios)     INFERRED_TARGET="ipa" ;;
    esac
  fi

  if [ "$DIST_PLAYSTORE" = true ]; then
    if [ -n "$INFERRED_TARGET" ] && [ "$INFERRED_TARGET" = "apk" ]; then
      echo "❌ Cannot combine firebase (android → apk) with playstore (→ appbundle) in one run."
      echo "   Run them separately."
      exit 1
    fi
    INFERRED_TARGET="appbundle"
  fi

  if [ "$DIST_APPSTORE" = true ]; then
    if [ -n "$INFERRED_TARGET" ] && [ "$INFERRED_TARGET" != "ipa" ]; then
      echo "❌ Cannot combine appstore (→ ipa) with android targets in one run."
      echo "   Run them separately."
      exit 1
    fi
    INFERRED_TARGET="ipa"
  fi

  TARGET="$INFERRED_TARGET"
fi

# Default target if still empty
TARGET="${TARGET:-appbundle}"

# Infer platform from target when not explicitly set (for Firebase validation later)
if [ "$DIST_FIREBASE" = true ] && [ -z "$PLATFORM" ]; then
  case "$TARGET" in
    apk|appbundle) PLATFORM="android" ;;
    ipa)           PLATFORM="ios" ;;
  esac
fi

# ==========================================
# DEPENDENCY & CREDENTIAL CHECKS
# ==========================================
check_dependencies() {
  local missing=false

  if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew is not installed."
    echo "   Install from: https://brew.sh"
    missing=true
  fi

  if ! command -v ruby &>/dev/null; then
    echo "❌ Ruby is not installed."
    echo "   Install with: brew install ruby"
    missing=true
  fi

  if ! command -v fastlane &>/dev/null; then
    echo "❌ Fastlane is not installed."
    echo "   Install with: brew install fastlane"
    missing=true
  fi

  if ! command -v bundle &>/dev/null; then
    echo "❌ Bundler is not installed."
    echo "   Install with: brew install fastlane  (includes bundler)"
    missing=true
  fi

  if [ "$missing" = true ]; then
    echo ""
    echo "Please install the missing dependencies and try again."
    exit 1
  fi
}

validate_credentials() {
  local valid=true

  if [ "$DIST_FIREBASE" = true ]; then
    if [ "$PLATFORM" = "android" ] && [ -z "$FIREBASE_APP_ID_ANDROID" ]; then
      echo "❌ Missing: FIREBASE_APP_ID_ANDROID"
      valid=false
    fi
    if [ "$PLATFORM" = "ios" ] && [ -z "$FIREBASE_APP_ID_IOS" ]; then
      echo "❌ Missing: FIREBASE_APP_ID_IOS"
      valid=false
    fi
    if [ -z "$FIREBASE_CLI_TOKEN" ]; then
      echo "❌ Missing: FIREBASE_CLI_TOKEN"
      echo "   Generate with: firebase login:ci"
      valid=false
    fi
  fi

  if [ "$DIST_PLAYSTORE" = true ]; then
    if [ -z "$ANDROID_PACKAGE_NAME" ]; then
      echo "❌ Could not detect Android package name (applicationId)."
      echo "   Please set ANDROID_PACKAGE_NAME in .build_release.env or pass --package-name <pkg>"
      valid=false
    fi
    if [ -z "$GOOGLE_PLAY_JSON_KEY" ]; then
      echo "❌ Missing: GOOGLE_PLAY_JSON_KEY"
      valid=false
    else
      local resolved_key
      resolved_key="$(eval echo "$GOOGLE_PLAY_JSON_KEY")"
      if [ ! -f "$resolved_key" ]; then
        echo "❌ Google Play JSON key file not found: $resolved_key"
        valid=false
      fi
    fi
  fi

  # --- Android signing check (release builds for Play Store) ---
  if [ "$BUILD_MODE" = "release" ] && { [ "$TARGET" = "appbundle" ] || [ "$TARGET" = "apk" ]; }; then
    local key_props="android/key.properties"
    if [ ! -f "$key_props" ]; then
      if [ "$DIST_PLAYSTORE" = true ]; then
        echo "❌ Android signing not configured: $key_props not found."
        echo "   Release builds without signing will be rejected by Google Play."
        echo "   See: https://docs.flutter.dev/deployment/android#sign-the-app"
        valid=false
      elif [ "$DIST_FIREBASE" = true ]; then
        echo "⚠️  No $key_props found — APK will be signed with debug key."
        echo "   This is OK for Firebase, but not for Play Store."
      fi
    else
      # Verify storeFile exists
      local store_file
      store_file=$(grep "^storeFile" "$key_props" 2>/dev/null | head -1 | cut -d'=' -f2- | xargs)
      if [ -n "$store_file" ]; then
        local found=false
        if [[ "$store_file" = /* ]] || [[ "$store_file" == ~* ]]; then
          local resolved_store
          resolved_store="$(eval echo "$store_file")"
          if [ -f "$resolved_store" ]; then
            found=true
          fi
        else
          # Relative path can be relative to android/app/, android/, or project root
          for candidate in "android/app/$store_file" "android/$store_file" "$store_file"; do
            if [ -f "$candidate" ]; then
              found=true
              break
            fi
          done
        fi

        if [ "$found" = false ]; then
          echo "❌ Keystore file not found: $store_file (checked android/app/, android/) (from $key_props)"
          valid=false
        fi
      fi
    fi
  fi

  if [ "$DIST_APPSTORE" = true ]; then
    if [ -z "$ASC_KEY_ID" ]; then
      echo "❌ Missing: ASC_KEY_ID"
      valid=false
    fi
    if [ -z "$ASC_ISSUER_ID" ]; then
      echo "❌ Missing: ASC_ISSUER_ID"
      valid=false
    fi
    if [ -z "$ASC_KEY_FILE" ]; then
      echo "❌ Missing: ASC_KEY_FILE"
      valid=false
    else
      local resolved_key
      resolved_key="$(eval echo "$ASC_KEY_FILE")"
      if [ ! -f "$resolved_key" ]; then
        echo "❌ App Store Connect key file not found: $resolved_key"
        valid=false
      fi
    fi
  fi

  if [ "$valid" = false ]; then
    echo ""
    echo "Configure credentials in .build_release.env (see .build_release.env.example)."
    exit 1
  fi
}

# ==========================================
# FASTLANE BOOTSTRAP
# ==========================================
setup_fastlane() {
  echo "⚙️  Setting up Fastlane environment..."
  mkdir -p "$FASTLANE_WORK_DIR/fastlane"

  # --- Gemfile ---
  cat > "$FASTLANE_WORK_DIR/Gemfile" << 'GEMFILE_CONTENT'
source "https://rubygems.org"
gem "fastlane"

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
GEMFILE_CONTENT

  # --- Pluginfile ---
  if [ "$DIST_FIREBASE" = true ]; then
    cat > "$FASTLANE_WORK_DIR/fastlane/Pluginfile" << 'PLUGINFILE_CONTENT'
gem 'fastlane-plugin-firebase_app_distribution'
PLUGINFILE_CONTENT
  else
    echo "# No plugins required" > "$FASTLANE_WORK_DIR/fastlane/Pluginfile"
  fi

  # --- Fastfile ---
  cat > "$FASTLANE_WORK_DIR/fastlane/Fastfile" << 'FASTFILE_CONTENT'
# Auto-generated by build_release.sh — do not edit manually.

default_platform(:android)

lane :distribute_firebase do |options|
  params = {
    app: options[:app_id],
    firebase_cli_token: options[:firebase_cli_token]
  }

  if options[:artifact_type] == 'ipa'
    params[:ipa_path] = options[:artifact_path]
  else
    params[:android_artifact_path] = options[:artifact_path]
  end

  params[:groups] = options[:groups] unless options[:groups].to_s.strip.empty?
  params[:release_notes] = options[:release_notes] unless options[:release_notes].to_s.strip.empty?

  firebase_app_distribution(params)
end

lane :distribute_playstore do |options|
  upload_to_play_store(
    package_name: options[:package_name],
    aab: options[:artifact_path],
    json_key: options[:json_key],
    track: options[:track] || 'internal',
    skip_upload_metadata: true,
    skip_upload_images: true,
    skip_upload_screenshots: true
  )
end

lane :distribute_appstore do |options|
  api_key = app_store_connect_api_key(
    key_id: options[:key_id],
    issuer_id: options[:issuer_id],
    key_filepath: options[:key_file]
  )

  upload_to_testflight(
    api_key: api_key,
    ipa: options[:artifact_path],
    skip_waiting_for_build_processing: true
  )
end
FASTFILE_CONTENT

  # --- Install gems ---
  echo "📦 Installing Fastlane dependencies (this may take a moment on first run)..."
  (cd "$FASTLANE_WORK_DIR" && bundle config set --local path vendor/bundle &>/dev/null && bundle install --quiet 2>&1)
}

run_fastlane_lane() {
  local lane="$1"
  shift
  (cd "$FASTLANE_WORK_DIR" && bundle exec fastlane "$lane" "$@")
}

# ==========================================
# DISTRIBUTE FUNCTIONS
# ==========================================
distribute_to_firebase() {
  local artifact_path="$1"
  local abs_path="$PROJECT_ROOT/$artifact_path"
  local app_id artifact_type

  if [ "$PLATFORM" = "android" ]; then
    app_id="$FIREBASE_APP_ID_ANDROID"
    artifact_type="apk"
  else
    app_id="$FIREBASE_APP_ID_IOS"
    artifact_type="ipa"
  fi

  echo ""
  echo "🔥 Firebase App Distribution"
  echo "   App ID    : $app_id"
  echo "   Platform  : $PLATFORM"
  echo "   Artifact  : $artifact_path"
  [ -n "$DIST_GROUPS" ] && echo "   Groups    : $DIST_GROUPS"
  [ -n "$DIST_NOTES" ]  && echo "   Notes     : $DIST_NOTES"

  if [ "$DRY_RUN" = true ]; then
    echo "   🏃 DRY RUN — upload skipped."
    return 0
  fi

  run_fastlane_lane distribute_firebase \
    "app_id:$app_id" \
    "artifact_path:$abs_path" \
    "artifact_type:$artifact_type" \
    "groups:$DIST_GROUPS" \
    "release_notes:$DIST_NOTES" \
    "firebase_cli_token:$FIREBASE_CLI_TOKEN"

  echo "   ✅ Firebase distribution complete."
}

distribute_to_playstore() {
  local artifact_path="$1"
  local abs_path="$PROJECT_ROOT/$artifact_path"
  local resolved_key
  resolved_key="$(eval echo "$GOOGLE_PLAY_JSON_KEY")"

  echo ""
  echo "🏪 Google Play Store"
  echo "   Track     : $PLAY_TRACK"
  echo "   Package   : $ANDROID_PACKAGE_NAME"
  echo "   Artifact  : $artifact_path"

  if [ "$DRY_RUN" = true ]; then
    echo "   🏃 DRY RUN — upload skipped."
    return 0
  fi

  run_fastlane_lane distribute_playstore \
    "package_name:$ANDROID_PACKAGE_NAME" \
    "artifact_path:$abs_path" \
    "json_key:$resolved_key" \
    "track:$PLAY_TRACK"

  echo "   ✅ Play Store upload complete."
}

distribute_to_appstore() {
  local artifact_path="$1"
  local abs_path="$PROJECT_ROOT/$artifact_path"
  local resolved_key
  resolved_key="$(eval echo "$ASC_KEY_FILE")"

  echo ""
  echo "🍎 App Store Connect (TestFlight)"
  echo "   Key ID    : $ASC_KEY_ID"
  echo "   Artifact  : $artifact_path"

  if [ "$DRY_RUN" = true ]; then
    echo "   🏃 DRY RUN — upload skipped."
    return 0
  fi

  run_fastlane_lane distribute_appstore \
    "artifact_path:$abs_path" \
    "key_id:$ASC_KEY_ID" \
    "issuer_id:$ASC_ISSUER_ID" \
    "key_file:$resolved_key"

  echo "   ✅ TestFlight upload complete."
}

# ==========================================
# STEP COUNTER
# ==========================================
if [ "$DISTRIBUTE_ONLY" = true ]; then
  TOTAL_STEPS=3
elif [ "$HAS_DISTRIBUTE" = true ]; then
  TOTAL_STEPS=5
else
  TOTAL_STEPS=4
fi

CURRENT_STEP=0
step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo ""
  echo "$1 [$CURRENT_STEP/$TOTAL_STEPS] $2"
}

# ==========================================
# MAIN PIPELINE
# ==========================================
if [ "$DISTRIBUTE_ONLY" = true ]; then
  echo "🚀 Starting Distribute-Only Pipeline..."
else
  echo "🚀 Starting Build Pipeline ($BUILD_MODE) for '$TARGET'..."
fi

# ------------------------------------------
# STEP: PRE-FLIGHT CHECKS
# ------------------------------------------
step "🔍" "Pre-flight Checks & Validation..."

if [ "$HAS_DISTRIBUTE" = true ]; then
  check_dependencies
  validate_credentials
fi

if [ "$DISTRIBUTE_ONLY" = false ]; then
  if [[ -n $(git status -s) ]]; then
    if [ "$BUILD_MODE" = "release" ]; then
      echo "⚠️  WARNING: Working directory has uncommitted changes!"
      if [ -t 0 ]; then
        read -p "Continue with release build anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "❌ Build aborted."
          exit 1
        fi
      else
        echo "❌ Non-interactive environment with uncommitted changes. Aborting build."
        exit 1
      fi
    else
      echo "ℹ️  Note: Working directory has uncommitted changes (allowed in $BUILD_MODE mode)."
    fi
  fi
fi

# Version & build info
VERSION_NAME=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d '+' -f 1 | tr -d ' "')
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
DATE_TAG=$(date +"%Y%m%d_%H%M")

echo "📌 Version       : $VERSION_NAME+$BUILD_NUMBER"
echo "📌 Timestamp     : $DATE_TAG"
echo "📌 Build Mode    : $BUILD_MODE"
echo "📌 Target        : $TARGET"
if [ "$HAS_DISTRIBUTE" = true ]; then
  echo "📌 Distribute    : $DISTRIBUTE_TARGETS"
fi
if [ "$DRY_RUN" = true ]; then
  echo "📌 Dry Run       : YES (uploads will be skipped)"
fi

# Determine artifact naming
if [ "$BUILD_MODE" = "release" ]; then
  FILE_PREFIX="${APP_NAME}"
else
  FILE_PREFIX="${APP_NAME}_${BUILD_MODE}"
fi

case "$TARGET" in
  apk)       ARTIFACT_EXT="apk" ;;
  appbundle) ARTIFACT_EXT="aab" ;;
  ipa)       ARTIFACT_EXT="ipa" ;;
esac

DEST_FILE="$BUILD_DIR/${FILE_PREFIX}_v${VERSION_NAME}_b${BUILD_NUMBER}_${DATE_TAG}.${ARTIFACT_EXT}"

# ------------------------------------------
# DISTRIBUTE-ONLY: find existing artifact
# ------------------------------------------
if [ "$DISTRIBUTE_ONLY" = true ]; then
  FOUND_ARTIFACT=$(ls -t "$BUILD_DIR"/*."$ARTIFACT_EXT" 2>/dev/null | head -n 1 || true)
  if [ -z "$FOUND_ARTIFACT" ] || [ ! -f "$FOUND_ARTIFACT" ]; then
    echo "❌ No .$ARTIFACT_EXT artifact found in $BUILD_DIR/"
    echo "   Build first before using --distribute-only."
    exit 1
  fi
  DEST_FILE="$FOUND_ARTIFACT"
  echo "📦 Using existing artifact: $DEST_FILE"
fi

# ------------------------------------------
# STEP: CLEAN & DEPENDENCIES (skip if distribute-only)
# ------------------------------------------
if [ "$DISTRIBUTE_ONLY" = false ]; then
  step "🧹" "Cleaning previous build cache and fetching dependencies..."
  flutter clean
  flutter pub get

  # ------------------------------------------
  # STEP: BUILD ARTIFACTS
  # ------------------------------------------
  step "🔨" "Compiling target '$TARGET' in '$BUILD_MODE' mode..."

  mkdir -p "$BUILD_DIR"

  COMMON_ARGS=(
    "--$BUILD_MODE"
    "--build-name=$VERSION_NAME"
    "--build-number=$BUILD_NUMBER"
  )

  SYMBOLS_OUTPUT=""
  if [ "$ENABLE_OBFUSCATE" = true ]; then
    if [ "$BUILD_MODE" = "debug" ]; then
      echo "⚠️  WARNING: Obfuscation is not supported in debug mode. Disabling."
      ENABLE_OBFUSCATE=false
    else
      mkdir -p "$SYMBOLS_DIR"
      if [ "$BUILD_MODE" = "release" ]; then
        SYMBOLS_OUTPUT="$SYMBOLS_DIR/symbols_v${VERSION_NAME}_b${BUILD_NUMBER}_${DATE_TAG}"
      else
        SYMBOLS_OUTPUT="$SYMBOLS_DIR/symbols_${BUILD_MODE}_v${VERSION_NAME}_b${BUILD_NUMBER}_${DATE_TAG}"
      fi
      COMMON_ARGS+=(
        "--obfuscate"
        "--split-debug-info=$SYMBOLS_OUTPUT"
      )
      echo "🔒 Obfuscation enabled. Debug symbols: $SYMBOLS_OUTPUT"
    fi
  fi

  case "$TARGET" in
    "appbundle")
      flutter build appbundle "${COMMON_ARGS[@]}"
      OUTPUT_FILE="build/app/outputs/bundle/${BUILD_MODE}/app-${BUILD_MODE}.aab"
      if [ ! -f "$OUTPUT_FILE" ]; then
        OUTPUT_FILE=$(find build/app/outputs/bundle -name "*.aab" -type f | head -n 1)
      fi
      if [ -f "$OUTPUT_FILE" ]; then
        cp "$OUTPUT_FILE" "$DEST_FILE"
      else
        echo "❌ Error: Could not find generated .aab file."
        exit 1
      fi
      ;;
    "apk")
      flutter build apk "${COMMON_ARGS[@]}"
      OUTPUT_FILE="build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"
      if [ ! -f "$OUTPUT_FILE" ]; then
        OUTPUT_FILE=$(find build/app/outputs/flutter-apk -name "*${BUILD_MODE}*.apk" -type f | head -n 1)
      fi
      if [ -f "$OUTPUT_FILE" ]; then
        cp "$OUTPUT_FILE" "$DEST_FILE"
      else
        echo "❌ Error: Could not find generated .apk file."
        exit 1
      fi
      ;;
    "ipa")
      IPA_BUILD_ARGS=("${COMMON_ARGS[@]}")
      if [ -n "$IOS_EXPORT_OPTIONS_PLIST" ] && [ -f "$IOS_EXPORT_OPTIONS_PLIST" ]; then
        IPA_BUILD_ARGS+=("--export-options-plist=$IOS_EXPORT_OPTIONS_PLIST")
        echo "📋 Using export options: $IOS_EXPORT_OPTIONS_PLIST"
      fi
      flutter build ipa "${IPA_BUILD_ARGS[@]}"
      IPA_FILE=$(ls build/ios/ipa/*.ipa 2>/dev/null | head -n 1 || true)
      if [ -n "$IPA_FILE" ] && [ -f "$IPA_FILE" ]; then
        cp "$IPA_FILE" "$DEST_FILE"
      else
        echo "⚠️  No .ipa found in build/ios/ipa/."
        if [ "$HAS_DISTRIBUTE" = true ]; then
          echo "❌ Cannot distribute without .ipa artifact. Check Xcode signing config."
          exit 1
        fi
        echo "   If archive was generated, check build/ios/archive/."
      fi
      ;;
  esac
fi

# ------------------------------------------
# STEP: DISTRIBUTE (if requested)
# ------------------------------------------
if [ "$HAS_DISTRIBUTE" = true ]; then
  step "📤" "Distributing to: $DISTRIBUTE_TARGETS"

  if [ ! -f "$DEST_FILE" ]; then
    echo "❌ Artifact not found: $DEST_FILE"
    exit 1
  fi

  setup_fastlane

  if [ "$DIST_FIREBASE" = true ]; then
    distribute_to_firebase "$DEST_FILE"
  fi

  if [ "$DIST_PLAYSTORE" = true ]; then
    distribute_to_playstore "$DEST_FILE"
  fi

  if [ "$DIST_APPSTORE" = true ]; then
    distribute_to_appstore "$DEST_FILE"
  fi
fi

# ------------------------------------------
# STEP: SUMMARY
# ------------------------------------------
SUMMARY_LABEL="BUILD"
if [ "$HAS_DISTRIBUTE" = true ]; then
  if [ "$DISTRIBUTE_ONLY" = true ]; then
    SUMMARY_LABEL="DISTRIBUTE"
  else
    SUMMARY_LABEL="BUILD & DISTRIBUTE"
  fi
fi

echo ""
echo "=========================================="
echo "✅ $SUMMARY_LABEL FINISHED SUCCESSFULLY!"
echo "🎯 Mode         : $BUILD_MODE"
echo "🎯 Target       : $TARGET"
if [ -f "$DEST_FILE" ]; then
  echo "📦 Artifact     : $DEST_FILE"
else
  echo "📦 Output Dir   : $BUILD_DIR"
fi
if [ -n "$SYMBOLS_OUTPUT" ]; then
  echo "📂 Debug Symbols: $SYMBOLS_OUTPUT"
fi
if [ "$HAS_DISTRIBUTE" = true ]; then
  echo "📤 Distributed  : $DISTRIBUTE_TARGETS"
  if [ "$DRY_RUN" = true ]; then
    echo "🏃 Dry Run      : Uploads were skipped"
  fi
fi
echo "=========================================="
