#!/usr/bin/env bash
# Build & run FOLDSPACE on a regular iPhone simulator (any Xcode 26.3+). The on-screen hinge control
# feeds the same HingeEngine the iPhone Duo's onHingeChange does.
#
#   scripts/build-sim.sh                  # iPhone 17 Pro
#   DEVICE="iPhone 17" scripts/build-sim.sh
#   DEMO=blackhole scripts/build-sim.sh   # jump straight to a demo state (see FoldspaceApp.applyDemoStateIfRequested)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DEVICE="${DEVICE:-iPhone 17 Pro}"

UDID=$(xcrun simctl list devices available | grep "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
[[ -n "$UDID" ]] || { echo "No available simulator named '$DEVICE'. Create one in Xcode → Window → Devices and Simulators."; exit 1; }

xcodegen generate >/dev/null
xcodebuild -project Foldspace.xcodeproj -scheme Foldspace \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet build

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/Foldspace.app
if [[ -n "${DEMO:-}" ]]; then
  SIMCTL_CHILD_FOLDSPACE_DEMO="$DEMO" xcrun simctl launch --terminate-running-process "$UDID" com.vnmoorthy.foldspace
else
  xcrun simctl launch --terminate-running-process "$UDID" com.vnmoorthy.foldspace
fi
