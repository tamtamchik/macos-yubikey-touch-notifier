#!/bin/bash
# Install macos-yubikey-touch-notifier as a launchd agent.
#   curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/install.sh | bash
set -euo pipefail

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }

# Install the latest published release; fall back to main if none exists.
TAG="$(curl -fsSL https://api.github.com/repos/tamtamchik/macos-yubikey-touch-notifier/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')"
REPO="https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/${TAG:-main}"
PREFIX=/usr/local
LABEL=com.tamtamchik.yubikey-touch-notifier
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

command -v terminal-notifier >/dev/null || {
    command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }
    echo "Installing terminal-notifier..."
    brew install terminal-notifier
}

echo "Installing to $PREFIX (sudo required)..."
curl -fsSL "$REPO/yubikey-touch-notifier" | sudo tee "$PREFIX/bin/yubikey-touch-notifier" >/dev/null
sudo chmod 755 "$PREFIX/bin/yubikey-touch-notifier"
sudo install -d "$PREFIX/share/yubikey-touch-notifier"
curl -fsSL "$REPO/icon.png" | sudo tee "$PREFIX/share/yubikey-touch-notifier/icon.png" >/dev/null

mkdir -p "$HOME/Library/LaunchAgents"
curl -fsSL "$REPO/$LABEL.plist" -o "$PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Done. Test it with a touch-required operation, e.g.:"
echo "  echo test | gpg --clearsign >/dev/null"
