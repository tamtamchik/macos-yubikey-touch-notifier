#!/bin/bash
# Install macos-yubikey-touch-notifier as a launchd agent.
#   curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/install.sh | bash
set -euo pipefail

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }
# Per-user LaunchAgent: as root it would load for root, not you. The script sudo's where needed.
[ "$(id -u)" = 0 ] && { echo "Run as your user, not root (it sudo's where needed)." >&2; exit 1; }

# Install the latest published release; fall back to main if none exists.
TAG="$(curl -fsSL https://api.github.com/repos/tamtamchik/macos-yubikey-touch-notifier/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')" || true
REF="${TAG:-main}"
REPO="https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/$REF"
PREFIX=/usr/local
LABEL=com.tamtamchik.yubikey-touch-notifier
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$PREFIX/bin/yubikey-touch-notifier"
SHARE="$PREFIX/share/yubikey-touch-notifier"

echo "Installing yubikey-touch-notifier ($REF) to $PREFIX"

# terminal-notifier delivers the actual macOS notification; pull it via Homebrew if missing.
if command -v terminal-notifier >/dev/null; then
    echo "  [1/5] terminal-notifier already present"
else
    command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }
    # Ask before installing a dependency. Read from the tty since stdin is the curl pipe.
    read -r -p "  [1/5] terminal-notifier is required but not installed. Install via Homebrew? [Y/n] " ans </dev/tty || ans=n
    case "$ans" in
        [nN]*) echo "Aborted: terminal-notifier is required." >&2; exit 1 ;;
        *) echo "  [1/5] installing terminal-notifier via Homebrew..."; brew install terminal-notifier ;;
    esac
fi

# Binary and icon live under $PREFIX, which needs root.
echo "  [2/5] installing binary -> $BIN (sudo required)"
sudo install -d "$PREFIX/bin"
curl -fsSL "$REPO/yubikey-touch-notifier" | sudo tee "$BIN" >/dev/null
sudo chmod 755 "$BIN"

echo "  [3/5] installing icon -> $SHARE/icon.png"
sudo install -d "$SHARE"
curl -fsSL "$REPO/icon.png" | sudo tee "$SHARE/icon.png" >/dev/null

echo "  [4/5] installing launch agent -> $PLIST"
mkdir -p "$HOME/Library/LaunchAgents"
curl -fsSL "$REPO/$LABEL.plist" -o "$PLIST"

echo "  [5/5] (re)loading launch agent"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

# Summary of what landed on disk.
echo
echo "Installed:"
echo "  $BIN"
echo "  $SHARE/icon.png"
echo "  $PLIST"

# Confirm the agent actually registered with launchd.
if launchctl list | grep -qF "$LABEL"; then
    echo "Agent loaded: $LABEL"
else
    echo "Warning: $LABEL did not load. Check $PLIST and /tmp/yubikey-touch-notifier.err" >&2
fi

echo
echo "Test it with a touch-required operation, e.g.:"
echo "  echo test | gpg --clearsign >/dev/null"
