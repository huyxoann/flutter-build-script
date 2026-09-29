#!/bin/bash
set -e

# ==========================================
# Self-check for resolve_ios_export_options
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the function from build_release.sh without running the whole script
# Extract resolve_ios_export_options into a subshell function
eval "$(sed -n '/^resolve_ios_export_options() {/,/^}/p' "$REPO_ROOT/scripts/build_release.sh")"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

cd "$TEMP_DIR"
BUILD_MODE="release"
BUILD_DIR="build/dist"

# --- Test 1: Explicit env var ---
IOS_EXPORT_OPTIONS_PLIST="$TEMP_DIR/custom_export.plist"
touch "$IOS_EXPORT_OPTIONS_PLIST"
RESULT=$(resolve_ios_export_options)
[ "$RESULT" = "$IOS_EXPORT_OPTIONS_PLIST" ] || { echo "❌ Test 1 failed"; exit 1; }
echo "✅ Test 1 (explicit env var): PASS"

# --- Test 2: Existing ios/ExportOptions.plist ---
IOS_EXPORT_OPTIONS_PLIST=""
mkdir -p ios
touch ios/ExportOptions.plist
RESULT=$(resolve_ios_export_options)
[ "$RESULT" = "ios/ExportOptions.plist" ] || { echo "❌ Test 2 failed"; exit 1; }
echo "✅ Test 2 (existing plist): PASS"

# --- Test 3: Auto-generate from pbxproj ---
rm -f ios/ExportOptions.plist
mkdir -p ios/Runner.xcodeproj
cat > ios/Runner.xcodeproj/project.pbxproj << 'EOF'
/* Runner */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = 97C147051CF9000F007C117D;
    name = Runner;
};
97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */ = {
    isa = XCConfigurationList;
    buildConfigurations = (
        97C147071CF9000F007C117D /* Release */,
    );
};
97C147071CF9000F007C117D /* Release */ = {
    isa = XCBuildConfiguration;
    buildSettings = {
        CODE_SIGN_STYLE = Manual;
        DEVELOPMENT_TEAM = "";
        "DEVELOPMENT_TEAM[sdk=iphoneos*]" = TESTTEAM123;
        PRODUCT_BUNDLE_IDENTIFIER = com.example.testapp;
        PROVISIONING_PROFILE_SPECIFIER = "";
        "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "Test App Profile";
    };
};
EOF

RESULT=$(resolve_ios_export_options)
[ "$RESULT" = "build/dist/ExportOptions.generated.plist" ] || { echo "❌ Test 3 path failed"; exit 1; }
[ -f "$RESULT" ] || { echo "❌ Test 3 file missing"; exit 1; }

python3 -c "
import plistlib
with open('$RESULT', 'rb') as f:
    p = plistlib.load(f)
assert p['method'] == 'app-store'
assert p['signingStyle'] == 'manual'
assert p['teamID'] == 'TESTTEAM123'
assert p['provisioningProfiles']['com.example.testapp'] == 'Test App Profile'
assert p['signingCertificate'] == 'Apple Distribution'
"
echo "✅ Test 3 (auto-generate manual): PASS"

echo "🎉 All checks passed!"
