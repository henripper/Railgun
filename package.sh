#!/bin/bash
# Builds the app and packs it into a drag-to-Applications disk image.
# Usage: ./package.sh [suffix]    e.g. ./package.sh beta.1  ->  build/Railgun-0.1.0-beta.1.dmg
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
NAME="Railgun-$VERSION${1:+-$1}"
STAGING=build/dmg
DMG="build/$NAME.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Railgun.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Railgun" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "Packaged $DMG"
shasum -a 256 "$DMG"
