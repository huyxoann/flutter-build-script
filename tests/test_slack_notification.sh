#!/bin/bash
set -e

# ==========================================
# Self-check for Slack Notification logic
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

eval "$(sed -n '/^# SLACK NOTIFICATION/,/^# BUILD NUMBER RESOLUTION/p' "$REPO_ROOT/scripts/build_release.sh")"

# --- Test 1: format_slack_mention ---
[ "$(format_slack_mention "here")" = "<!here>" ] || { echo "❌ Test 1a failed"; exit 1; }
[ "$(format_slack_mention "@channel")" = "<!channel>" ] || { echo "❌ Test 1b failed"; exit 1; }
[ "$(format_slack_mention "<@U12345>")" = "<@U12345>" ] || { echo "❌ Test 1c failed"; exit 1; }
echo "✅ Test 1 (format_slack_mention): PASS"

# --- Test 2: build_slack_payload generates valid JSON with expected fields ---
APP_NAME="demo_app"
VERSION_NAME="1.2.3"
BUILD_NUMBER="45"
BUILD_MODE="release"
TARGET="ipa"
DIST_FIREBASE=true
DIST_GROUPS="QA,PM"
DIST_PLAYSTORE=false
PLAY_TRACK="internal"
DIST_APPSTORE=true
DISTRIBUTE_TARGETS="firebase,appstore"
SLACK_MENTION="here"

PAYLOAD=$(build_slack_payload)

PAYLOAD="$PAYLOAD" python3 -c '
import json, os
data = json.loads(os.environ["PAYLOAD"])
assert "New Build Distributed: demo_app v1.2.3+45" in data["text"]
blocks = data["blocks"]
assert blocks[0]["type"] == "header"
assert "demo_app v1.2.3+45" in blocks[0]["text"]["text"]
fields = blocks[1]["fields"]
assert len(fields) == 4
assert "demo_app" in fields[0]["text"]
assert "\n" in fields[0]["text"] and "\\n" not in fields[0]["text"]
assert "iOS (IPA)" in fields[1]["text"]
assert "Firebase (groups: QA,PM), TestFlight" in fields[2]["text"]
assert "<!here>" in blocks[2]["text"]["text"]
'
echo "✅ Test 2 (build_slack_payload valid Block Kit JSON): PASS"

# --- Test 3: notify_slack dry-run and --no-slack ---
NO_SLACK=false
DRY_RUN=true
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T000/B000/XXXX"
OUT=$(notify_slack)
echo "$OUT" | grep -q "DRY RUN — Slack notification skipped" || { echo "❌ Test 3a failed"; exit 1; }

NO_SLACK=true
OUT_NO_SLACK=$(notify_slack)
[ -z "$OUT_NO_SLACK" ] || { echo "❌ Test 3b failed"; exit 1; }
echo "✅ Test 3 (notify_slack dry-run & --no-slack): PASS"

# --- Test 4: notify_slack non-fatal warning on failure ---
NO_SLACK=false
DRY_RUN=false
SLACK_WEBHOOK_URL="http://127.0.0.1:9/invalid"
OUT_FAIL=$(notify_slack)
echo "$OUT_FAIL" | grep -q "WARNING: Failed to send Slack notification" || { echo "❌ Test 4 failed"; exit 1; }
echo "✅ Test 4 (notify_slack non-fatal warning on error): PASS"

echo "🎉 All Slack notification checks passed!"
