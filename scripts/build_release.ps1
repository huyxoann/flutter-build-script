$ErrorActionPreference = 'Stop'

# ==========================================
# FLUTTER BUILD & DISTRIBUTE SCRIPT (PowerShell)
# ==========================================
# Builds Flutter artifacts (APK, AAB) and optionally distributes
# them to Firebase App Distribution or Google Play Store via Fastlane.
# iOS builds are not supported on Windows.
#
# Run with --help for usage.

# Resolve project root: if script lives in <project>\scripts\, use that.
# Otherwise (global install / symlink), use the current working directory.
$SCRIPT_PARENT = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if (Test-Path (Join-Path $SCRIPT_PARENT "pubspec.yaml")) {
    $PROJECT_ROOT = $SCRIPT_PARENT
} else {
    $PROJECT_ROOT = [System.IO.Path]::GetFullPath($PWD.Path)
}

if (-not (Test-Path (Join-Path $PROJECT_ROOT "pubspec.yaml"))) {
    Write-Host "❌ No pubspec.yaml found in $PROJECT_ROOT" -ForegroundColor Red
    Write-Host "   Run this command from the root of a Flutter project." -ForegroundColor Red
    exit 1
}
Set-Location -Path $PROJECT_ROOT

$APP_NAME = Split-Path $PROJECT_ROOT -Leaf
$BUILD_DIR = "build\dist"
$SYMBOLS_DIR = "$BUILD_DIR\symbols"
$FASTLANE_WORK_DIR = "$BUILD_DIR\.fastlane"

# ==========================================
# DEFAULTS
# ==========================================
$TARGET = ""
$BUILD_MODE = "release"
$ENABLE_OBFUSCATE = $false
$DISTRIBUTE_TARGETS = ""
$PLATFORM = ""
$PLAY_TRACK = "internal"
$DIST_GROUPS = ""
$DIST_NOTES = ""
$DISTRIBUTE_ONLY = $false
$DRY_RUN = $false

# Config defaults (overridden by .build_release.env)
$FIREBASE_APP_ID_ANDROID = ""
$FIREBASE_APP_ID_IOS = ""
$FIREBASE_CLI_TOKEN = ""
$FIREBASE_TESTER_GROUPS = ""
$FIREBASE_RELEASE_NOTES = ""
$GOOGLE_PLAY_JSON_KEY = ""

# ==========================================
# LOAD PROJECT CONFIG
# ==========================================
if (Test-Path ".build_release.env") {
    $envLines = Get-Content ".build_release.env"
    foreach ($line in $envLines) {
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith("#")) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -gt 0) {
            $key = $line.Substring(0, $idx).Trim()
            $value = $line.Substring($idx + 1).Trim()
            # Remove wrapping quotes if any
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            # Handle ~ in paths
            $value = $value.Replace("~", $env:USERPROFILE)
            Set-Variable -Name $key -Value $value -Scope Script
        }
    }
}

# ==========================================
# PROJECT SETUP
# ==========================================
function Run-Setup {
    Write-Host "⚙️  Setting up project for build_release..." -ForegroundColor Cyan
    Write-Host ""

    # --- .build_release.env ---
    if (Test-Path ".build_release.env") {
        Write-Host "⚠️  .build_release.env already exists." -ForegroundColor Yellow
        $ans = Read-Host "Overwrite? (y/N)"
        if ($ans -notmatch "^[Yy]$") {
            Write-Host "   Skipped .build_release.env"
        } else {
            Create-EnvFile
        }
    } else {
        Create-EnvFile
    }

    # --- .gitignore ---
    if (Test-Path ".gitignore") {
        $gitignore = Get-Content ".gitignore"
        if ($gitignore -notcontains ".build_release.env") {
            Add-Content ".gitignore" "`n# Build release config (contains secrets)`n.build_release.env"
            Write-Host "✅ Added .build_release.env to .gitignore" -ForegroundColor Green
        } else {
            Write-Host "ℹ️  .build_release.env already in .gitignore" -ForegroundColor Cyan
        }
    } else {
        Set-Content ".gitignore" "# Build release config (contains secrets)`n.build_release.env"
        Write-Host "✅ Created .gitignore with .build_release.env" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "🚀 Setup complete! Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Edit .build_release.env with your credentials"
    Write-Host "   2. Run: .\build_release.ps1 --distribute firebase --platform android"
    exit 0
}

function Create-EnvFile {
    $envTemplate = @"
# ==========================================
# .build_release.env — Project Build & Distribution Config
# ==========================================
# ⚠️  Do NOT commit this file — it contains secrets!

# === Firebase App Distribution ===
# App IDs from Firebase Console > Project Settings > General > Your apps
FIREBASE_APP_ID_ANDROID=
FIREBASE_APP_ID_IOS=

# Firebase CLI token (generate with: firebase login:ci)
FIREBASE_CLI_TOKEN=

# Default tester groups (comma-separated, can override with --groups)
FIREBASE_TESTER_GROUPS=

# Default release notes (can override with --notes)
FIREBASE_RELEASE_NOTES=

# === Google Play Store ===
# Path to service account JSON key file
# Create at: Google Cloud Console > IAM > Service Accounts
GOOGLE_PLAY_JSON_KEY=

# === App Store Connect (API Key — macOS only) ===
# Create at: App Store Connect > Users and Access > Integrations
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_KEY_FILE=

# === iOS Build (Optional) ===
# Path to ExportOptions.plist for manual signing (omit for Xcode automatic signing)
# IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.plist
"@
    Set-Content -Path ".build_release.env" -Value $envTemplate -Encoding UTF8
    Write-Host "✅ Created .build_release.env" -ForegroundColor Green
}

# ==========================================
# HELP
# ==========================================
function Show-Help {
    @"
Usage: .\build_release.ps1 [TARGET] [MODE] [OPTIONS]

Targets:
  appbundle                Build Android App Bundle (.aab) [Default]
  apk                      Build Android APK (.apk)
  ipa                      Build iOS IPA (.ipa) [Unsupported on Windows]

Build Modes:
  release, --release       Build release version [Default]
  profile, --profile       Build profile version (for performance profiling)
  debug,   --debug         Build debug version

Distribution:
  --distribute <targets>   Comma-separated: firebase, playstore
  --platform <os>          android (required for firebase)
  --track <track>          Google Play track: internal, alpha, beta, production [Default: internal]
  --groups <groups>        Firebase tester groups, comma-separated
  --notes <text>           Release notes for Firebase distribution
  --distribute-only        Skip build, distribute latest artifact from build\dist\
  --dry-run                Validate config and build, but skip actual upload

Options:
  --setup                  Setup project credentials and .build_release.env
  --obfuscate              Enable Dart symbol obfuscation (release/profile only)
  --help, -h               Show this help message

Examples:
  # Build Android App Bundle (default, no distribution)
  .\build_release.ps1

  # Build & distribute APK to Firebase
  .\build_release.ps1 --distribute firebase --platform android

  # Build & upload AAB to Google Play (internal track)
  .\build_release.ps1 --distribute playstore

  # Re-distribute existing artifact (skip build)
  .\build_release.ps1 --distribute firebase --platform android --distribute-only

  # Dry-run (validate everything, skip actual upload)
  .\build_release.ps1 --distribute playstore --dry-run

Config:
  Create .build_release.env at your project root (see .build_release.env.example).
  Add .build_release.env to .gitignore — it contains secrets.
"@ | Write-Host
    exit 0
}

# ==========================================
# PARSE ARGUMENTS
# ==========================================
$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    switch -Regex ($arg) {
        "^(appbundle|apk|ipa)$" {
            $TARGET = $arg; $i++; break
        }
        "^(release|--release)$" {
            $BUILD_MODE = "release"; $i++; break
        }
        "^(profile|--profile)$" {
            $BUILD_MODE = "profile"; $i++; break
        }
        "^(debug|--debug)$" {
            $BUILD_MODE = "debug"; $i++; break
        }
        "^--obfuscate$" {
            $ENABLE_OBFUSCATE = $true; $i++; break
        }
        "^--distribute$" {
            if ($i + 1 -lt $args.Count) { $DISTRIBUTE_TARGETS = $args[$i+1]; $i += 2 } else { Write-Host "❌ Missing value for --distribute" -ForegroundColor Red; exit 1 }; break
        }
        "^--distribute=(.*)$" {
            $DISTRIBUTE_TARGETS = $Matches[1]; $i++; break
        }
        "^--platform$" {
            if ($i + 1 -lt $args.Count) { $PLATFORM = $args[$i+1]; $i += 2 } else { Write-Host "❌ Missing value for --platform" -ForegroundColor Red; exit 1 }; break
        }
        "^--platform=(.*)$" {
            $PLATFORM = $Matches[1]; $i++; break
        }
        "^--track$" {
            if ($i + 1 -lt $args.Count) { $PLAY_TRACK = $args[$i+1]; $i += 2 } else { Write-Host "❌ Missing value for --track" -ForegroundColor Red; exit 1 }; break
        }
        "^--track=(.*)$" {
            $PLAY_TRACK = $Matches[1]; $i++; break
        }
        "^--groups$" {
            if ($i + 1 -lt $args.Count) { $DIST_GROUPS = $args[$i+1]; $i += 2 } else { Write-Host "❌ Missing value for --groups" -ForegroundColor Red; exit 1 }; break
        }
        "^--groups=(.*)$" {
            $DIST_GROUPS = $Matches[1]; $i++; break
        }
        "^--notes$" {
            if ($i + 1 -lt $args.Count) { $DIST_NOTES = $args[$i+1]; $i += 2 } else { Write-Host "❌ Missing value for --notes" -ForegroundColor Red; exit 1 }; break
        }
        "^--notes=(.*)$" {
            $DIST_NOTES = $Matches[1]; $i++; break
        }
        "^--distribute-only$" {
            $DISTRIBUTE_ONLY = $true; $i++; break
        }
        "^--dry-run$" {
            $DRY_RUN = $true; $i++; break
        }
        "^--setup$" {
            Run-Setup
        }
        "^(-h|--help)$" {
            Show-Help
        }
        default {
            Write-Host "❌ Unknown argument: $arg" -ForegroundColor Red
            Write-Host "Run '.\build_release.ps1 --help' for usage." -ForegroundColor Red
            exit 1
        }
    }
}

# Apply defaults from config (CLI flags take priority)
if ([string]::IsNullOrEmpty($DIST_GROUPS)) { $DIST_GROUPS = $FIREBASE_TESTER_GROUPS }
if ([string]::IsNullOrEmpty($DIST_NOTES)) { $DIST_NOTES = $FIREBASE_RELEASE_NOTES }

# ==========================================
# VALIDATE DISTRIBUTE TARGETS & INFER BUILD TARGET
# ==========================================
$HAS_DISTRIBUTE = $false
$DIST_FIREBASE = $false
$DIST_PLAYSTORE = $false

if (-not [string]::IsNullOrEmpty($DISTRIBUTE_TARGETS)) {
    $HAS_DISTRIBUTE = $true
    $distArray = $DISTRIBUTE_TARGETS.Split(',')
    foreach ($dist in $distArray) {
        switch ($dist.Trim()) {
            "firebase"  { $DIST_FIREBASE = $true }
            "playstore" { $DIST_PLAYSTORE = $true }
            "appstore"  { 
                Write-Host "❌ iOS builds are not supported on Windows. Use macOS." -ForegroundColor Red
                exit 1 
            }
            default {
                Write-Host "❌ Unknown distribute target: $dist" -ForegroundColor Red
                Write-Host "   Valid targets: firebase, playstore" -ForegroundColor Red
                exit 1
            }
        }
    }
}

if ($TARGET -eq "ipa") {
    Write-Host "❌ iOS builds are not supported on Windows. Use macOS." -ForegroundColor Red
    exit 1
}

if ($DISTRIBUTE_ONLY -and -not $HAS_DISTRIBUTE) {
    Write-Host "❌ --distribute-only requires --distribute <targets>." -ForegroundColor Red
    exit 1
}

# Validate --platform value
if (-not [string]::IsNullOrEmpty($PLATFORM) -and $PLATFORM -ne "android" -and $PLATFORM -ne "ios") {
    Write-Host "❌ Invalid platform: $PLATFORM" -ForegroundColor Red
    Write-Host "   Valid values: android" -ForegroundColor Red
    exit 1
}

if ($PLATFORM -eq "ios") {
    Write-Host "❌ iOS builds are not supported on Windows. Use macOS." -ForegroundColor Red
    exit 1
}

# Auto-infer build target from distribute targets
if ($HAS_DISTRIBUTE -and [string]::IsNullOrEmpty($TARGET)) {
    $INFERRED_TARGET = ""

    if ($DIST_FIREBASE) {
        if ([string]::IsNullOrEmpty($PLATFORM)) {
            Write-Host "❌ --platform android is required when distributing to firebase." -ForegroundColor Red
            exit 1
        }
        if ($PLATFORM -eq "android") {
            $INFERRED_TARGET = "apk"
        }
    }

    if ($DIST_PLAYSTORE) {
        if (-not [string]::IsNullOrEmpty($INFERRED_TARGET) -and $INFERRED_TARGET -eq "apk") {
            Write-Host "❌ Cannot combine firebase (android → apk) with playstore (→ appbundle) in one run." -ForegroundColor Red
            Write-Host "   Run them separately." -ForegroundColor Red
            exit 1
        }
        $INFERRED_TARGET = "appbundle"
    }

    $TARGET = $INFERRED_TARGET
}

# Default target if still empty
if ([string]::IsNullOrEmpty($TARGET)) {
    $TARGET = "appbundle"
}

# Infer platform from target when not explicitly set (for Firebase validation later)
if ($DIST_FIREBASE -and [string]::IsNullOrEmpty($PLATFORM)) {
    if ($TARGET -eq "apk" -or $TARGET -eq "appbundle") {
        $PLATFORM = "android"
    }
}

# ==========================================
# DEPENDENCY & CREDENTIAL CHECKS
# ==========================================
function Check-Dependencies {
    $missing = $false

    if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Ruby is not installed." -ForegroundColor Red
        Write-Host "   Install with: choco install ruby" -ForegroundColor Red
        $missing = $true
    }

    if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Bundler is not installed." -ForegroundColor Red
        Write-Host "   Install with: gem install bundler" -ForegroundColor Red
        $missing = $true
    }

    if (-not (Get-Command fastlane -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Fastlane is not installed." -ForegroundColor Red
        Write-Host "   Install with: gem install fastlane" -ForegroundColor Red
        $missing = $true
    }

    if ($missing) {
        Write-Host "`nPlease install the missing dependencies and try again."
        exit 1
    }
}

function Validate-Credentials {
    $valid = $true

    if ($DIST_FIREBASE) {
        if ($PLATFORM -eq "android" -and [string]::IsNullOrEmpty($FIREBASE_APP_ID_ANDROID)) {
            Write-Host "❌ Missing: FIREBASE_APP_ID_ANDROID" -ForegroundColor Red
            $valid = $false
        }
        if ([string]::IsNullOrEmpty($FIREBASE_CLI_TOKEN)) {
            Write-Host "❌ Missing: FIREBASE_CLI_TOKEN" -ForegroundColor Red
            Write-Host "   Generate with: firebase login:ci" -ForegroundColor Red
            $valid = $false
        }
    }

    if ($DIST_PLAYSTORE) {
        if ([string]::IsNullOrEmpty($GOOGLE_PLAY_JSON_KEY)) {
            Write-Host "❌ Missing: GOOGLE_PLAY_JSON_KEY" -ForegroundColor Red
            $valid = $false
        } else {
            $resolved_key = $GOOGLE_PLAY_JSON_KEY
            if (-not (Test-Path $resolved_key)) {
                Write-Host "❌ Google Play JSON key file not found: $resolved_key" -ForegroundColor Red
                $valid = $false
            }
        }
    }

    if (-not $valid) {
        Write-Host "`nConfigure credentials in .build_release.env (see .build_release.env.example)."
        exit 1
    }
}

# ==========================================
# FASTLANE BOOTSTRAP
# ==========================================
function Setup-Fastlane {
    Write-Host "⚙️  Setting up Fastlane environment..." -ForegroundColor Cyan
    $fastlaneDir = Join-Path $FASTLANE_WORK_DIR "fastlane"
    New-Item -ItemType Directory -Force -Path $fastlaneDir | Out-Null

    # --- Gemfile ---
    $gemfileContent = @"
source "https://rubygems.org"
gem "fastlane"

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
"@
    Set-Content -Path (Join-Path $FASTLANE_WORK_DIR "Gemfile") -Value $gemfileContent -Encoding UTF8

    # --- Pluginfile ---
    if ($DIST_FIREBASE) {
        $pluginfileContent = "gem 'fastlane-plugin-firebase_app_distribution'"
        Set-Content -Path (Join-Path $fastlaneDir "Pluginfile") -Value $pluginfileContent -Encoding UTF8
    } else {
        Set-Content -Path (Join-Path $fastlaneDir "Pluginfile") -Value "# No plugins required" -Encoding UTF8
    }

    # --- Fastfile ---
    $fastfileContent = @"
# Auto-generated by build_release.ps1 — do not edit manually.

default_platform(:android)

lane :distribute_firebase do |options|
  params = {
    app: options[:app_id],
    firebase_cli_token: options[:firebase_cli_token]
  }

  params[:android_artifact_path] = options[:artifact_path]

  params[:groups] = options[:groups] unless options[:groups].to_s.strip.empty?
  params[:release_notes] = options[:release_notes] unless options[:release_notes].to_s.strip.empty?

  firebase_app_distribution(params)
end

lane :distribute_playstore do |options|
  upload_to_play_store(
    aab: options[:artifact_path],
    json_key: options[:json_key],
    track: options[:track] || 'internal',
    skip_upload_metadata: true,
    skip_upload_images: true,
    skip_upload_screenshots: true
  )
end
"@
    Set-Content -Path (Join-Path $fastlaneDir "Fastfile") -Value $fastfileContent -Encoding UTF8

    # --- Install gems ---
    Write-Host "📦 Installing Fastlane dependencies (this may take a moment on first run)..." -ForegroundColor Cyan
    Push-Location $FASTLANE_WORK_DIR
    try {
        bundle install --path vendor/bundle --quiet
        if ($LASTEXITCODE -ne 0) { throw "bundle install failed" }
    } finally {
        Pop-Location
    }
}

function Run-FastlaneLane {
    param([string]$lane, [string[]]$argsParams)
    Push-Location $FASTLANE_WORK_DIR
    try {
        $cmdArgs = @("exec", "fastlane", $lane) + $argsParams
        bundle $cmdArgs
        if ($LASTEXITCODE -ne 0) { throw "fastlane $lane failed" }
    } finally {
        Pop-Location
    }
}

# ==========================================
# DISTRIBUTE FUNCTIONS
# ==========================================
function Distribute-ToFirebase {
    param([string]$ArtifactPath)
    $abs_path = [System.IO.Path]::GetFullPath((Join-Path $PROJECT_ROOT $ArtifactPath))
    $abs_path = $abs_path -replace '\\', '/'
    
    $app_id = $FIREBASE_APP_ID_ANDROID
    $artifact_type = "apk"

    Write-Host "`n🔥 Firebase App Distribution"
    Write-Host "   App ID    : $app_id"
    Write-Host "   Platform  : $PLATFORM"
    Write-Host "   Artifact  : $ArtifactPath"
    if (-not [string]::IsNullOrEmpty($DIST_GROUPS)) { Write-Host "   Groups    : $DIST_GROUPS" }
    if (-not [string]::IsNullOrEmpty($DIST_NOTES)) { Write-Host "   Notes     : $DIST_NOTES" }

    if ($DRY_RUN) {
        Write-Host "   🏃 DRY RUN — upload skipped." -ForegroundColor Yellow
        return
    }

    Run-FastlaneLane -lane "distribute_firebase" -argsParams @(
        "app_id:$app_id",
        "artifact_path:$abs_path",
        "artifact_type:$artifact_type",
        "groups:$DIST_GROUPS",
        "release_notes:$DIST_NOTES",
        "firebase_cli_token:$FIREBASE_CLI_TOKEN"
    )

    Write-Host "   ✅ Firebase distribution complete." -ForegroundColor Green
}

function Distribute-ToPlaystore {
    param([string]$ArtifactPath)
    $abs_path = [System.IO.Path]::GetFullPath((Join-Path $PROJECT_ROOT $ArtifactPath))
    $abs_path = $abs_path -replace '\\', '/'
    $resolved_key = $GOOGLE_PLAY_JSON_KEY -replace '\\', '/'

    Write-Host "`n🏪 Google Play Store"
    Write-Host "   Track     : $PLAY_TRACK"
    Write-Host "   Artifact  : $ArtifactPath"

    if ($DRY_RUN) {
        Write-Host "   🏃 DRY RUN — upload skipped." -ForegroundColor Yellow
        return
    }

    Run-FastlaneLane -lane "distribute_playstore" -argsParams @(
        "artifact_path:$abs_path",
        "json_key:$resolved_key",
        "track:$PLAY_TRACK"
    )

    Write-Host "   ✅ Play Store upload complete." -ForegroundColor Green
}

# ==========================================
# STEP COUNTER
# ==========================================
if ($DISTRIBUTE_ONLY) { $TOTAL_STEPS = 3 }
elseif ($HAS_DISTRIBUTE) { $TOTAL_STEPS = 5 }
else { $TOTAL_STEPS = 4 }

$script:CURRENT_STEP = 0
function Step {
    param([string]$Emoji, [string]$Message)
    $script:CURRENT_STEP += 1
    Write-Host ""
    Write-Host "$Emoji [$script:CURRENT_STEP/$TOTAL_STEPS] $Message" -ForegroundColor Cyan
}

# ==========================================
# MAIN PIPELINE
# ==========================================
try {
    if ($DISTRIBUTE_ONLY) {
        Write-Host "🚀 Starting Distribute-Only Pipeline..." -ForegroundColor Cyan
    } else {
        Write-Host "🚀 Starting Build Pipeline ($BUILD_MODE) for '$TARGET'..." -ForegroundColor Cyan
    }

    # ------------------------------------------
    # STEP: PRE-FLIGHT CHECKS
    # ------------------------------------------
    Step "🔍" "Pre-flight Checks & Validation..."

    if ($HAS_DISTRIBUTE) {
        Check-Dependencies
        Validate-Credentials
    }

    if (-not $DISTRIBUTE_ONLY) {
        $gitStatus = git status -s
        if ($LASTEXITCODE -ne 0) { throw "git status failed" }
        if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
            if ($BUILD_MODE -eq "release") {
                Write-Host "⚠️  WARNING: Working directory has uncommitted changes!" -ForegroundColor Yellow
                $ans = Read-Host "Continue with release build anyway? (y/N)"
                if ($ans -notmatch "^[Yy]$") {
                    Write-Host "❌ Build aborted." -ForegroundColor Red
                    exit 1
                }
            } else {
                Write-Host "ℹ️  Note: Working directory has uncommitted changes (allowed in $BUILD_MODE mode)." -ForegroundColor Cyan
            }
        }
    }

    # Version & build info
    $pubspec = Get-Content "pubspec.yaml"
    $VERSION_NAME = ""
    foreach ($line in $pubspec) {
        if ($line -match "^version:\s*(.*)") {
            $VERSION_NAME = $Matches[1].Split('+')[0].Trim(" `"'")
            break
        }
    }
    
    $BUILD_NUMBER = (git rev-list --count HEAD 2>$null)
    if ([string]::IsNullOrWhiteSpace($BUILD_NUMBER)) { $BUILD_NUMBER = "1" }
    
    $DATE_TAG = Get-Date -Format "yyyyMMdd_HHmm"

    Write-Host "📌 Version       : $VERSION_NAME+$BUILD_NUMBER" -ForegroundColor Cyan
    Write-Host "📌 Timestamp     : $DATE_TAG" -ForegroundColor Cyan
    Write-Host "📌 Build Mode    : $BUILD_MODE" -ForegroundColor Cyan
    Write-Host "📌 Target        : $TARGET" -ForegroundColor Cyan
    if ($HAS_DISTRIBUTE) { Write-Host "📌 Distribute    : $DISTRIBUTE_TARGETS" -ForegroundColor Cyan }
    if ($DRY_RUN) { Write-Host "📌 Dry Run       : YES (uploads will be skipped)" -ForegroundColor Cyan }

    # Determine artifact naming
    if ($BUILD_MODE -eq "release") {
        $FILE_PREFIX = $APP_NAME
    } else {
        $FILE_PREFIX = "${APP_NAME}_${BUILD_MODE}"
    }

    switch ($TARGET) {
        "apk"       { $ARTIFACT_EXT = "apk" }
        "appbundle" { $ARTIFACT_EXT = "aab" }
    }

    $DEST_FILE = Join-Path $BUILD_DIR "${FILE_PREFIX}_v${VERSION_NAME}_b${BUILD_NUMBER}_${DATE_TAG}.${ARTIFACT_EXT}"
    $DEST_FILE_FORWARD = $DEST_FILE -replace '\\', '/'

    # ------------------------------------------
    # DISTRIBUTE-ONLY: find existing artifact
    # ------------------------------------------
    if ($DISTRIBUTE_ONLY) {
        $foundFiles = Get-ChildItem -Path $BUILD_DIR -Filter "*.$ARTIFACT_EXT" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($foundFiles.Count -eq 0) {
            Write-Host "❌ No .$ARTIFACT_EXT artifact found in $BUILD_DIR\" -ForegroundColor Red
            Write-Host "   Build first before using --distribute-only." -ForegroundColor Red
            exit 1
        }
        $DEST_FILE = $foundFiles[0].FullName
        $DEST_FILE_FORWARD = $DEST_FILE -replace '\\', '/'
        Write-Host "📦 Using existing artifact: $DEST_FILE_FORWARD" -ForegroundColor Cyan
    }

    # ------------------------------------------
    # STEP: CLEAN & DEPENDENCIES (skip if distribute-only)
    # ------------------------------------------
    if (-not $DISTRIBUTE_ONLY) {
        Step "🧹" "Cleaning previous build cache and fetching dependencies..."
        flutter clean
        if ($LASTEXITCODE -ne 0) { throw "flutter clean failed" }
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

        # ------------------------------------------
        # STEP: BUILD ARTIFACTS
        # ------------------------------------------
        Step "🔨" "Compiling target '$TARGET' in '$BUILD_MODE' mode..."

        New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null

        $COMMON_ARGS = @(
            "--$BUILD_MODE",
            "--build-name=$VERSION_NAME",
            "--build-number=$BUILD_NUMBER"
        )

        $SYMBOLS_OUTPUT = ""
        if ($ENABLE_OBFUSCATE) {
            if ($BUILD_MODE -eq "debug") {
                Write-Host "⚠️  WARNING: Obfuscation is not supported in debug mode. Disabling." -ForegroundColor Yellow
                $ENABLE_OBFUSCATE = $false
            } else {
                New-Item -ItemType Directory -Force -Path $SYMBOLS_DIR | Out-Null
                if ($BUILD_MODE -eq "release") {
                    $SYMBOLS_OUTPUT = Join-Path $SYMBOLS_DIR "symbols_v${VERSION_NAME}_b${BUILD_NUMBER}_${DATE_TAG}"
                } else {
                    $SYMBOLS_OUTPUT = Join-Path $SYMBOLS_DIR "symbols_${BUILD_MODE}_v${VERSION_NAME}_b${BUILD_NUMBER}_${DATE_TAG}"
                }
                $COMMON_ARGS += "--obfuscate"
                $COMMON_ARGS += "--split-debug-info=$($SYMBOLS_OUTPUT -replace '\\', '/')"
                Write-Host "🔒 Obfuscation enabled. Debug symbols: $SYMBOLS_OUTPUT" -ForegroundColor Cyan
            }
        }

        switch ($TARGET) {
            "appbundle" {
                flutter build appbundle $COMMON_ARGS
                if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle failed" }
                
                $OUTPUT_FILE = "build/app/outputs/bundle/${BUILD_MODE}/app-${BUILD_MODE}.aab"
                if (-not (Test-Path $OUTPUT_FILE)) {
                    $found = Get-ChildItem -Path "build/app/outputs/bundle" -Filter "*.aab" -Recurse -File -ErrorAction SilentlyContinue
                    if ($found.Count -gt 0) { $OUTPUT_FILE = $found[0].FullName }
                }
                
                if (Test-Path $OUTPUT_FILE) {
                    Copy-Item -Path $OUTPUT_FILE -Destination $DEST_FILE -Force
                } else {
                    Write-Host "❌ Error: Could not find generated .aab file." -ForegroundColor Red
                    exit 1
                }
            }
            "apk" {
                flutter build apk $COMMON_ARGS
                if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
                
                $OUTPUT_FILE = "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"
                if (-not (Test-Path $OUTPUT_FILE)) {
                    $found = Get-ChildItem -Path "build/app/outputs/flutter-apk" -Filter "*${BUILD_MODE}*.apk" -Recurse -File -ErrorAction SilentlyContinue
                    if ($found.Count -gt 0) { $OUTPUT_FILE = $found[0].FullName }
                }
                
                if (Test-Path $OUTPUT_FILE) {
                    Copy-Item -Path $OUTPUT_FILE -Destination $DEST_FILE -Force
                } else {
                    Write-Host "❌ Error: Could not find generated .apk file." -ForegroundColor Red
                    exit 1
                }
            }
        }
    }

    # ------------------------------------------
    # STEP: DISTRIBUTE (if requested)
    # ------------------------------------------
    if ($HAS_DISTRIBUTE) {
        Step "📤" "Distributing to: $DISTRIBUTE_TARGETS"

        if (-not (Test-Path $DEST_FILE)) {
            Write-Host "❌ Artifact not found: $DEST_FILE_FORWARD" -ForegroundColor Red
            exit 1
        }

        Setup-Fastlane

        if ($DIST_FIREBASE) {
            Distribute-ToFirebase $DEST_FILE_FORWARD
        }

        if ($DIST_PLAYSTORE) {
            Distribute-ToPlaystore $DEST_FILE_FORWARD
        }
    }

    # ------------------------------------------
    # STEP: SUMMARY
    # ------------------------------------------
    $SUMMARY_LABEL = "BUILD"
    if ($HAS_DISTRIBUTE) {
        if ($DISTRIBUTE_ONLY) { $SUMMARY_LABEL = "DISTRIBUTE" }
        else { $SUMMARY_LABEL = "BUILD & DISTRIBUTE" }
    }

    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "✅ $SUMMARY_LABEL FINISHED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "🎯 Mode         : $BUILD_MODE" -ForegroundColor Green
    Write-Host "🎯 Target       : $TARGET" -ForegroundColor Green
    if (Test-Path $DEST_FILE) {
        Write-Host "📦 Artifact     : $DEST_FILE_FORWARD" -ForegroundColor Green
    } else {
        Write-Host "📦 Output Dir   : $($BUILD_DIR -replace '\\', '/')" -ForegroundColor Green
    }
    if (-not [string]::IsNullOrEmpty($SYMBOLS_OUTPUT)) {
        Write-Host "📂 Debug Symbols: $($SYMBOLS_OUTPUT -replace '\\', '/')" -ForegroundColor Green
    }
    if ($HAS_DISTRIBUTE) {
        Write-Host "📤 Distributed  : $DISTRIBUTE_TARGETS" -ForegroundColor Green
        if ($DRY_RUN) { Write-Host "🏃 Dry Run      : Uploads were skipped" -ForegroundColor Green }
    }
    Write-Host "==========================================" -ForegroundColor Green

} catch {
    Write-Host "`n❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
