#!/bin/bash
# Build, sign, notarize and staple a distributable YubiKey Touch Notifier.app.
# One-time: store your app-specific password (appleid.apple.com) in the keychain:
#   xcrun notarytool store-credentials notary-yubikey \
#       --apple-id you@example.com --team-id 4ZQ23V678N --password APP_SPECIFIC_PASSWORD
# Then: ./app/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Use the first Developer ID Application identity in the keychain unless overridden.
CODESIGN_ID="${CODESIGN_ID:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
[ -n "$CODESIGN_ID" ] || { echo "no Developer ID Application certificate found"; exit 1; }

APP="build/YubiKey Touch Notifier.app"
ZIP="build/YubiKeyTouchNotifier.zip"
PROFILE="${NOTARY_PROFILE:-notary-yubikey}"

CODESIGN_ID="$CODESIGN_ID" ./app/build.sh

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip with the stapled ticket so the download passes Gatekeeper offline.
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "release: $ZIP"
