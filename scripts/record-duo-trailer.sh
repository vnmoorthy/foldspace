#!/usr/bin/env bash
# Record the 3-minute FOLDSPACE submission video on the iPhone Duo simulator (Xcode 27.1+).
#  1. builds with the native hinge API (DUO_SDK) and installs on an iPhone Duo simulator
#  2. plays each key moment through the FOLDSPACE_DEMO hook and records it (simctl io recordVideo)
#  3. intercuts the clips with the deck slides (docs/FOLDSPACE-Deck.pdf) on the exact timing of
#     docs/PRESENTATION-SCRIPT.md → docs/media/foldspace-submission-3min.mp4 (1920×1080, 180 s, silent)
# Add your voice-over afterwards with: scripts/add-voiceover.sh voice.mp3
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT=docs/media
WORK=$(mktemp -d)
mkdir -p "$OUT"
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
FONT=/System/Library/Fonts/HelveticaNeue.ttc

RUNTIME=$(xcrun simctl list runtimes | grep -E "iOS 27" | tail -1 | sed -E 's/.* - (com\.apple\.[^ ]+).*/\1/')
[[ -n "$RUNTIME" ]] || { echo "No iOS 27 runtime installed (xcodebuild -downloadPlatform iOS)"; exit 1; }
UDID=$(xcrun simctl list devices available | grep "iPhone Duo (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
[[ -n "$UDID" ]] || UDID=$(xcrun simctl create "iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "$RUNTIME")
echo "iPhone Duo: $UDID ($RUNTIME)"

xcodegen generate >/dev/null
xcodebuild -project Foldspace.xcodeproj -scheme Foldspace -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build-duo CODE_SIGNING_ALLOWED=NO SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DUO_SDK' -quiet build

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 2>/dev/null || true
xcrun simctl install "$UDID" build-duo/Build/Products/Debug-iphonesimulator/Foldspace.app
xcrun simctl io "$UDID" enumerate > "$OUT/duo-displays.txt" 2>&1 || true

rec () { # name state seconds
  local name="$1" state="$2" secs="$3"
  SIMCTL_CHILD_FOLDSPACE_DEMO="$state" xcrun simctl launch --terminate-running-process "$UDID" com.vnmoorthy.foldspace >/dev/null
  sleep 0.8
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$WORK/raw-$name.mp4" 2>/dev/null &
  local pid=$!
  sleep "$((secs + 1))"
  kill -INT "$pid"; wait "$pid" 2>/dev/null || true
  xcrun simctl io "$UDID" screenshot "$OUT/duo-$name.png" >/dev/null 2>&1 || true
  echo "recorded $name ($state, $secs s)"
}
rec c1  cockpit   14
rec gal galaxy     7
rec out outer      6
rec c2  cockpit   15
rec wrp warp      19
rec sun sun       11
rec wpn weapon     9
rec bh  blackhole 10
rec and andromeda  6

# Deck slides → 1920×1080 PNGs
pdftoppm -png -r 144 docs/FOLDSPACE-Deck.pdf "$WORK/slide" >/dev/null
slide () { ls "$WORK"/slide-*.png | sed -n "$1p"; }

# Segment builders (all 1920×1080, 30 fps, yuv420p, silent)
seg_slide () { # n seconds out
  "$FF" -y -loglevel error -loop 1 -t "$2" -i "$(slide "$1")" \
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,fps=30,format=yuv420p,fade=t=in:st=0:d=0.4" \
    -c:v libx264 -crf 20 -preset veryfast "$3"
}
caption_png () { # text out  — transparent 1920×1080 overlay (ffmpeg here has no drawtext)
  python3 - "$1" "$2" "$FONT" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont
text, out, font = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
def f(size, idx):
    try: return ImageFont.truetype(font, size, index=idx)
    except Exception: return ImageFont.load_default()
small, big = f(20, 0), f(34, 0)
def spaced(s): return " ".join(s)  # wide letter-spacing, SpaceX-style
d.text((80, 1080 - 160), spaced("iPHONE DUO SIMULATOR"), font=small, fill=(61, 242, 255, 230))
d.line((80, 1080 - 128, 380, 1080 - 128), fill=(61, 242, 255, 200), width=2)
d.text((80, 1080 - 112), spaced(text), font=big, fill=(255, 255, 255, 225))
im.save(out)
PY
}
seg_clip () { # name seconds caption out
  local cap="$WORK/cap-$1.png"; caption_png "$3" "$cap"
  "$FF" -y -loglevel error -i "$WORK/raw-$1.mp4" -loop 1 -i "$cap" -t "$2" \
    -filter_complex "[0:v]scale=1800:1000:force_original_aspect_ratio=decrease:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,fps=30[v];[v][1:v]overlay=0:0:shortest=1,format=yuv420p,fade=t=in:st=0:d=0.3" \
    -c:v libx264 -crf 20 -preset veryfast "$4"
}
i=0; n () { i=$((i+1)); printf '%s/seg-%02d.mp4' "$WORK" "$i"; }
# Timing mirrors docs/PRESENTATION-SCRIPT.md (20·14·18·12·20·24·24·20·14·14 = 180 s)
seg_slide 1 6  "$(n)"; seg_clip c1  14 "OPEN IT TO FLY"                  "$(n)"   # 1  title        20
seg_slide 2 14 "$(n)"                                                             # 2  insight      14
seg_slide 3 5  "$(n)"; seg_clip gal 7  "LAY IT FLAT  ·  GALAXY MAP"      "$(n)"   # 3  ship         18
                       seg_clip out 6  "CLOSE IT  ·  THE OUTER DISPLAY"  "$(n)"
seg_slide 4 12 "$(n)"                                                             # 4  gestures     12
seg_slide 5 5  "$(n)"; seg_clip c2  15 "THE HOLOGRAM IN THE FOLD"        "$(n)"   # 5  hologram     20
seg_slide 6 5  "$(n)"; seg_clip wrp 19 "CLOSE IT SMOOTHLY  ·  FOLD SPACE" "$(n)"  # 6  warp         24
seg_slide 7 4  "$(n)"; seg_clip sun 11 "CLOSE IT NEAR THE SUN  ·  DIVE"  "$(n)"   # 7  sun + lance  24
                       seg_clip wpn 9  "SQUEEZE  ·  SNAP  ·  FIRE"        "$(n)"
seg_slide 8 4  "$(n)"; seg_clip bh  10 "FOLD  =  GRAVITY"                "$(n)"   # 8  the core     20
                       seg_clip and 6  "2,537,000 LIGHT-YEARS"           "$(n)"
seg_slide 9 14 "$(n)"                                                             # 9  built with   14
seg_slide 10 14 "$(n)"                                                            # 10 why before   14

ls "$WORK"/seg-*.mp4 | sed "s/^/file '/; s/$/'/" > "$WORK/list.txt"
"$FF" -y -loglevel error -f concat -safe 0 -i "$WORK/list.txt" -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart \
  "$OUT/foldspace-submission-3min.mp4"
# Short gameplay-only trailer + GIF for README / socials
ls "$WORK"/raw-*.mp4 >/dev/null
"$FF" -y -loglevel error -i "$OUT/foldspace-submission-3min.mp4" -ss 6 -t 14 -vf "fps=15,scale=480:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse" "$OUT/foldspace-duo.gif" || true
"$FF" -v error -show_entries format=duration -of csv=p=0 "$OUT/foldspace-submission-3min.mp4"
ls -la "$OUT"
echo "VIDEO: $OUT/foldspace-submission-3min.mp4"
