#!/bin/bash
# Build and sign YubiKey Touch Notifier.app.
#   CODESIGN_ID="Developer ID Application: ..." ./app/build.sh   # for release/notarization
#   ./app/build.sh                                              # local dev (Apple Development)
set -euo pipefail
cd "$(dirname "$0")/.."

# Ad-hoc by default so local builds need no keychain password.
# Release: CODESIGN_ID="Developer ID Application: ..." for a notarizable build.
APP="build/YubiKey Touch Notifier.app"
ID="${CODESIGN_ID:--}"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# icon.png (disc) -> native macOS squircle -> AppIcon.icns (standard iconset sizes).
SQUIRCLE=build/AppIcon.png
swift app/makeicon.swift icon.png "$SQUIRCLE"
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$SQUIRCLE" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$SQUIRCLE" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp app/Info.plist "$APP/Contents/Info.plist"
swiftc -O app/main.swift -o "$APP/Contents/MacOS/yubikey-touch-notifier"

# Hardened runtime so the same build is notarizable for release.
codesign --force --options runtime --sign "$ID" "$APP"
echo "built: $APP"
