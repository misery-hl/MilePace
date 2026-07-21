#!/usr/bin/env bash
#
# Build an iOS app, run it in the Simulator, and screenshot it.
#
# Expects a directory that is already patched to open on the screen you want to
# look at. This script only handles the mechanical part: build, boot, install,
# launch, settle, capture.
#
# Usage:
#   sim_preview.sh --dir <probe-dir> --bundle <id> [options]
#
# Options:
#   --dir      Directory holding the .xcodeproj to build (required)
#   --bundle   App bundle identifier, e.g. com.misery.MilePace (required)
#   --out      Screenshot path (default: <probe-dir>/../preview.png)
#   --scheme   Xcode scheme (default: MilePace)
#   --sim      Simulator device name (default: iPhone 17 Pro)
#   --settle   Seconds to wait after launch before capturing (default: 25)
#
# The settle default is deliberately generous. Map tiles, remote images, and
# other network-backed content render blank on a cold launch and fill in a few
# seconds later, so a fast screenshot will show an empty view and read as a bug
# that is not there.

set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

PROBE_DIR=""
BUNDLE_ID=""
OUT=""
SCHEME="MilePace"
SIM_NAME="iPhone 17 Pro"
SETTLE=25

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)    PROBE_DIR="$2"; shift 2 ;;
    --bundle) BUNDLE_ID="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --sim)    SIM_NAME="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$PROBE_DIR" ]] || { echo "error: --dir is required" >&2; exit 2; }
[[ -n "$BUNDLE_ID" ]] || { echo "error: --bundle is required" >&2; exit 2; }
[[ -d "$PROBE_DIR" ]] || { echo "error: no such directory: $PROBE_DIR" >&2; exit 2; }

OUT="${OUT:-$PROBE_DIR/../preview.png}"
BUILD_DIR="$PROBE_DIR/../PreviewBuild"
LOG="$PROBE_DIR/../preview_build.log"

echo "==> Building $SCHEME for $SIM_NAME"
if ! xcodebuild \
      -project "$PROBE_DIR"/*.xcodeproj \
      -scheme "$SCHEME" \
      -sdk iphonesimulator \
      -destination "platform=iOS Simulator,name=$SIM_NAME" \
      -derivedDataPath "$BUILD_DIR" \
      CODE_SIGNING_ALLOWED=NO \
      build > "$LOG" 2>&1; then
  echo "BUILD FAILED. Errors:" >&2
  grep -E "error:" "$LOG" | head -20 >&2
  exit 1
fi
echo "    build succeeded"

APP_PATH="$(find "$BUILD_DIR/Build/Products" -maxdepth 2 -name "*.app" | head -1)"
[[ -n "$APP_PATH" ]] || { echo "error: built .app not found" >&2; exit 1; }

UDID="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['name'] == name:
            print(d['udid'])
            sys.exit(0)
sys.exit(1)
" "$SIM_NAME")" || { echo "error: simulator '$SIM_NAME' not found. Available:" >&2
    xcrun simctl list devices available | grep -i iphone >&2; exit 1; }

echo "==> Booting $SIM_NAME ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || echo "    (already booted)"
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true

echo "==> Installing and launching $BUNDLE_ID"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" > /dev/null

echo "==> Waiting ${SETTLE}s for content to render"
sleep "$SETTLE"

xcrun simctl io "$UDID" screenshot "$OUT" > /dev/null 2>&1
echo "==> Screenshot: $OUT"
echo
echo "When finished, shut the simulator down with:"
echo "  DEVELOPER_DIR=$DEVELOPER_DIR xcrun simctl shutdown $UDID"
