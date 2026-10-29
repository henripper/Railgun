#!/bin/bash
# Builds build/Railgun.app with the Command Line Tools (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Railgun.app

# App icon: render once from tools/make-icon.swift, then reuse.
if [ ! -f Resources/Railgun.icns ]; then
    [ -f Resources/icon-1024.png ] || swift tools/make-icon.swift Resources/icon-1024.png
    ICONSET=build/Railgun.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for px in 16 32 128 256 512; do
        sips -z $px $px Resources/icon-1024.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
        sips -z $((px * 2)) $((px * 2)) Resources/icon-1024.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o Resources/Railgun.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.4 \
    Sources/*.swift -o "$APP/Contents/MacOS/Railgun"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Railgun.icns "$APP/Contents/Resources/Railgun.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
