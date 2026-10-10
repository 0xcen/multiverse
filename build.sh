#!/bin/bash
# Build Multiverse.app into ./build, or install it with: ./build.sh install
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Multiverse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/Multiverse-arm64"
swiftc -O -parse-as-library -target x86_64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/Multiverse-x86_64"
lipo -create "$APP/Contents/MacOS/Multiverse-arm64" "$APP/Contents/MacOS/Multiverse-x86_64" -output "$APP/Contents/MacOS/Multiverse"
rm "$APP/Contents/MacOS/Multiverse-"*
cp Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  # Make sure the old copy has really exited, or `open` would just bring it back to the front.
  osascript -e 'tell application id "io.github.0xcen.multiverse" to quit' 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Multiverse || break; sleep 0.5; done
  pkill -x Multiverse 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Multiverse.app
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Multiverse.app
  open /Applications/Multiverse.app
  echo "Installed /Applications/Multiverse.app"
fi
