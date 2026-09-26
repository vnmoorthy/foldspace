#!/usr/bin/env bash
# Build & run FOLDSPACE on the iPhone Duo simulator with the native hinge API (DUO_SDK).
# Requires Xcode 27.1 beta or newer (iOS 27.1 SDK) and the iPhone Duo simulator runtime.
#
#   scripts/build-duo.sh                       # auto-detects /Applications/Xcode-beta.app or Xcode_27*.app
#   XCODE=/Applications/Xcode-beta.app scripts/build-duo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

XCODE="${XCODE:-}"
if [[ -z "$XCODE" ]]; then
  for candidate in /Applications/Xcode-beta.app /Applications/Xcode_27*.app /Applications/Xcode27*.app /Applications/Xcode.app; do
    if [[ -d "$candidate" ]]; then
      v=$(defaults read "$candidate/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 0)
      if [[ "${v%%.*}" -ge 27 ]]; then XCODE="$candidate"; break; fi
    fi
  done
fi
[[ -n "$XCODE" ]] || { echo "No Xcode 27.x found. Install Xcode 27.1 beta from https://developer.apple.com/download/applications and set XCODE=/path/to/Xcode-beta.app"; exit 1; }
export DEVELOPER_DIR="$XCODE/Contents/Developer"
echo "Using $(xcodebuild -version | head -1) at $XCODE"

DUO_TYPE=$(xcrun simctl list devicetypes | grep -i "iPhone Duo" | head -1 | sed -E 's/.*\((com\.apple\.[^)]+)\).*/\1/')
[[ -n "$DUO_TYPE" ]] || { echo "This Xcode has no iPhone Duo simulator device type. Install the iOS 27.1 simulator runtime: xcodebuild -downloadPlatform iOS"; exit 1; }
RUNTIME=$(xcrun simctl list runtimes | grep -i "iOS 27" | tail -1 | sed -E 's/.*\((com\.apple\.[^)]+)\).*/\1/')
[[ -n "$RUNTIME" ]] || { echo "No iOS 27 simulator runtime. Run: xcodebuild -downloadPlatform iOS"; exit 1; }

UDID=$(xcrun simctl list devices available | grep -i "iPhone Duo" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl create "iPhone Duo" "$DUO_TYPE" "$RUNTIME")
  echo "Created iPhone Duo simulator $UDID"
fi

xcodegen generate >/dev/null
xcodebuild -project Foldspace.xcodeproj -scheme Foldspace \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build-duo CODE_SIGNING_ALLOWED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DUO_SDK' \
  -quiet build

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator
xcrun simctl install "$UDID" build-duo/Build/Products/Debug-iphonesimulator/Foldspace.app
xcrun simctl launch "$UDID" com.vnmoorthy.foldspace
echo "FOLDSPACE is running on the iPhone Duo simulator with the native hinge (DUO_SDK). Fold it from Device Hub / the Simulator's hinge control."
