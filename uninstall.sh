#!/bin/bash
# Uninstall macos-yubikey-touch-notifier.
#   curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/uninstall.sh | bash
set -euo pipefail

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }
# Per-user LaunchAgent: as root it would target root's, not yours. The script sudo's where needed.
[ "$(id -u)" = 0 ] && { echo "Run as your user, not root (it sudo's where needed)." >&2; exit 1; }

PREFIX=/usr/local
LABEL=com.tamtamchik.yubikey-touch-notifier
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$PREFIX/bin/yubikey-touch-notifier"
SHARE="$PREFIX/share/yubikey-touch-notifier"

echo "Uninstalling yubikey-touch-notifier from $PREFIX"

# Stop and deregister the agent before deleting its files.
echo "  [1/3] unloading launch agent -> $PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

# Binary and icon live under $PREFIX, which needs root.
# Keep going on a sudo failure so the leftover check below still runs (it exits non-zero).
echo "  [2/3] removing binary and icon (sudo required)"
sudo rm -f "$BIN" || true
sudo rm -rf "$SHARE" || true

echo "  [3/3] removing error log -> /tmp/yubikey-touch-notifier.err"
rm -f /tmp/yubikey-touch-notifier.err

# Report anything that survived removal.
echo
left=0
for p in "$PLIST" "$BIN" "$SHARE"; do
    [ -e "$p" ] && { echo "Still present: $p" >&2; left=1; }
done
if launchctl list "$LABEL" >/dev/null 2>&1; then
    echo "Still loaded: $LABEL" >&2
    left=1
fi
[ "$left" = 0 ] && echo "Removed cleanly."

echo
echo "terminal-notifier was left installed; remove it with: brew uninstall terminal-notifier"

# Non-zero exit if anything survived, so callers/automation can react.
exit "$left"
