#!/usr/bin/env bash
# Lay your voice-over (mp3/m4a/wav) over the 3-minute submission video.
#   scripts/add-voiceover.sh ~/Desktop/voice.mp3
# Output: docs/media/foldspace-submission-3min-voiced.mp4 (video untouched, audio normalised to -16 LUFS).
set -euo pipefail
cd "$(dirname "$0")/.."
VOICE="${1:?usage: scripts/add-voiceover.sh <voice.mp3>}"
IN=docs/media/foldspace-submission-3min.mp4
OUT=docs/media/foldspace-submission-3min-voiced.mp4
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
[[ -f "$IN" ]] || { echo "Missing $IN — run scripts/record-duo-trailer.sh first"; exit 1; }
"$FF" -y -loglevel error -i "$IN" -i "$VOICE" \
  -filter_complex "[1:a]loudnorm=I=-16:TP=-1.5:LRA=11,apad[a]" -map 0:v -map "[a]" \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"
echo "Done: $OUT"
