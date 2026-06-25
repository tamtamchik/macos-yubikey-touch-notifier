#!/bin/bash
# Build and sign YubiKey Touch Notifier.app.
#   CODESIGN_ID="Developer ID Application: ..." ./app/build.sh   # for release/notarization
#   ./app/build.sh                                              # local dev (ad-hoc signature)
set -euo pipefail
cd "$(dirname "$0")/.."

# Ad-hoc by default so local builds need no keychain password.
# Release: CODESIGN_ID="Developer ID Application: ..." for a notarizable build.
APP="build/YubiKey Touch Notifier.app"
ID="${CODESIGN_ID:--}"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Compile the Icon Composer document into the bundle (Assets.car + AppIcon.icns).
xcrun actool app/AppIcon.icon \
    --compile "$APP/Contents/Resources" \
    --app-icon AppIcon \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --output-partial-info-plist build/icon-partial.plist \
    --errors --warnings --output-format human-readable-text >/dev/null

cp app/Info.plist "$APP/Contents/Info.plist"
swiftc -O app/main.swift -o "$APP/Contents/MacOS/yubikey-touch-notifier"

# Hardened runtime so the same build is notarizable for release.
codesign --force --options runtime --sign "$ID" "$APP"
echo "built: $APP"
