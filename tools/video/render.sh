#!/bin/bash
# Render, encode and check the launch film. Run from the repo root. See RULES.md.
set -euo pipefail
# Usage: render.sh [out.mp4] [scale]   scale 2 = 3840×2160
OUT=${1:-docs/multiverse-launch.mp4}
export MV_SCALE=${2:-1}
W=$((1920 * MV_SCALE)); H=$((1080 * MV_SCALE))
WORK=$(mktemp -d)
BIN="$WORK/launch-video"
swiftc -O -parse-as-library -D SNAPSHOT Sources/*.swift tools/Carbon.swift tools/video/Pieces.swift tools/video/Film.swift \
  tools/video/Audio.swift tools/video/main.swift -o "$BIN"
FRAMES=$("$BIN" frames-count)

# Two-pass loudness normalisation to -16 LUFS: measure, then apply exactly.
loudnorm_filter() {
  ffmpeg -hide_banner -i "$1" -af loudnorm=I=-16:TP=-2:LRA=11:print_format=json -f null - 2>&1 | python3 -c "
import sys, json, re
j = json.loads(re.search(r'\{[^{}]*\}', sys.stdin.read(), re.S).group(0))
print('loudnorm=I=-16:TP=-2:LRA=11:linear=true:measured_I={input_i}:measured_TP={input_tp}:measured_LRA={input_lra}:measured_thresh={input_thresh}:offset={target_offset}'.format(**j))"
}
"$BIN" frames "$WORK/frames"
"$BIN" audio "$WORK/sound.wav"
ffmpeg -loglevel error -y -framerate 30 -i "$WORK/frames/%04d.png" -i "$WORK/sound.wav" \
  -c:v libx264 -preset slow -crf 18 -profile:v high -level 5.1 -pix_fmt yuv420p -vf "setsar=1" \
  -af "$(loudnorm_filter "$WORK/sound.wav"),alimiter=limit=0.75:level=false" -ar 48000 -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"

# Checks: these must all pass before anyone looks at the film.
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1: $2"; else echo "FAIL  $1: got $2, want $3"; fail=1; fi; }
check "frames rendered" "$(ls "$WORK/frames" | wc -l | tr -d ' ')" "$FRAMES"
probe() { ffprobe -v error -select_streams v:0 -show_entries "stream=$1" -of csv=p=0 "$OUT"; }
check "encoded frames" "$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$OUT")" "$FRAMES"
check "size" "$(probe width,height)" "$W,$H"
check "frame rate" "$(probe r_frame_rate)" "30/1"
check "pixel aspect" "$(probe sample_aspect_ratio)" "1:1"
check "pixel format" "$(probe pix_fmt)" "yuv420p"
# Audio: present, as long as the picture (within a frame), and not clipping.
check "audio stream" "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$OUT")" "aac"
vdur=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$OUT")
adur=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration -of csv=p=0 "$OUT")
check "audio matches picture" "$(python3 -c "print(abs($vdur-$adur) < 0.05)")" "True"
peak=$(ffmpeg -i "$OUT" -af volumedetect -f null - 2>&1 | grep max_volume | awk '{print $5}')
check "audio peak below -1 dB" "$(python3 -c "print($peak < -1)")" "True"
lufs=$(ffmpeg -i "$OUT" -af ebur128 -f null - 2>&1 | grep -E "^ +I:" | tail -1 | awk '{print $2}')
check "loudness about -16 LUFS (social)" "$(python3 -c "print(-17.5 < $lufs < -14.5)")" "True"
for n in 0 150 431 $((FRAMES - 1)); do
  check "re-render frame $n identical" "$("$BIN" same $n)" "same $n"
done

# Stills of each beat for the look pass.
rm -rf tools/video/checks && mkdir -p tools/video/checks
for t in 0.0 1.0 2.0 3.5 6.6 9.5 12.6 15.5 17.5 19.0 22.5 26.0 30.0 33.5 36.0 39.0; do
  ffmpeg -loglevel error -y -ss "$t" -i "$OUT" -frames:v 1 "tools/video/checks/t$t.png"
done
rm -rf "$WORK"
[ $fail = 0 ] && echo "All checks passed: $OUT ($(du -h "$OUT" | cut -f1))" || { echo "Checks failed"; exit 1; }
