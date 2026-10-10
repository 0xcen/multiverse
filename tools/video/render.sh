#!/bin/bash
# Render, encode and check the launch film. Run from the repo root. See RULES.md.
set -euo pipefail
OUT=${1:-docs/multiverse-launch.mp4}
WORK=$(mktemp -d)
BIN="$WORK/launch-video"
swiftc -O -parse-as-library -D SNAPSHOT Sources/*.swift tools/Carbon.swift tools/video/LaunchVideo.swift -o "$BIN"

"$BIN" frames "$WORK/frames"
ffmpeg -loglevel error -y -framerate 30 -i "$WORK/frames/%04d.png" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -vf "setsar=1" -movflags +faststart "$OUT"

# Checks: these must all pass before anyone looks at the film.
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1: $2"; else echo "FAIL  $1: got $2, want $3"; fail=1; fi; }
check "frames rendered" "$(ls "$WORK/frames" | wc -l | tr -d ' ')" 960
probe() { ffprobe -v error -select_streams v:0 -show_entries "stream=$1" -of csv=p=0 "$OUT"; }
check "encoded frames" "$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$OUT")" 960
check "size" "$(probe width,height)" "1920,1080"
check "frame rate" "$(probe r_frame_rate)" "30/1"
check "pixel aspect" "$(probe sample_aspect_ratio)" "1:1"
check "pixel format" "$(probe pix_fmt)" "yuv420p"
for n in 0 150 431 700 959; do
  check "re-render frame $n identical" "$("$BIN" same $n)" "same $n"
done

# Stills of each beat for the look pass.
mkdir -p tools/video/checks
for t in 1.5 4.8 8.8 10.5 13.0 17.8 21.8 23.5 26.0 30.0; do
  ffmpeg -loglevel error -y -ss "$t" -i "$OUT" -frames:v 1 "tools/video/checks/t$t.png"
done
rm -rf "$WORK"
[ $fail = 0 ] && echo "All checks passed: $OUT ($(du -h "$OUT" | cut -f1))" || { echo "Checks failed"; exit 1; }
