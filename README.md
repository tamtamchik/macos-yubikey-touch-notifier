<img alt="macos-yubikey-touch-notifier" src="https://github.com/user-attachments/assets/d1dff8d0-f174-4f73-9f9f-1bd369e9022d" />

# macOS Yubikey Touch Notifier

macOS notification when your YubiKey is waiting for a touch.

The signal is the unified log. The script tails `log stream` and matches two
cases:

- **FIDO2 / U2F** — a client that opened the YubiKey HID device calls `startQueue`.
- **OpenPGP** — the smartcard stack (`CryptoTokenKit`) emits `Time extension received`.

A single shell script over `log` + `awk` +
[`terminal-notifier`](https://github.com/julienXX/terminal-notifier) (it shows
the icon and **withdraws the banner once you touch the key**).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/install.sh | bash
```

Installs the latest published release (falls back to `main` if none exists).
Needs [Homebrew](https://brew.sh) (for `terminal-notifier`) and asks for `sudo`
to write into `/usr/local`.

<details>
<summary>Manual install</summary>

```sh
brew install terminal-notifier

sudo install -m 755 yubikey-touch-notifier /usr/local/bin/yubikey-touch-notifier
sudo install -d /usr/local/share/yubikey-touch-notifier
sudo install -m 644 icon.png /usr/local/share/yubikey-touch-notifier/icon.png

cp com.tamtamchik.yubikey-touch-notifier.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.tamtamchik.yubikey-touch-notifier.plist
```

</details>

Perform a touch-required operation — a GPG signature (`echo test | gpg
--clearsign`), an SSH auth, or a WebAuthn login — and a "Touch your YubiKey"
notification appears. (`gpg --card-status` does **not** request a touch, so it
will not trigger one.)

## Run in the foreground

```sh
./yubikey-touch-notifier
```

`YK_SOUND` sets the notification sound (default `Submarine`); `YK_SOUND=` mutes
it. `YK_ICON` overrides the banner icon path.

## Uninstall

```sh
launchctl unload ~/Library/LaunchAgents/com.tamtamchik.yubikey-touch-notifier.plist
rm ~/Library/LaunchAgents/com.tamtamchik.yubikey-touch-notifier.plist
sudo rm -rf /usr/local/bin/yubikey-touch-notifier /usr/local/share/yubikey-touch-notifier
```

## Notes

- Detection is heuristic, based on log messages, and may break on a future macOS
  release that renames them.
- The first time a banner fires, macOS may ask you to allow notifications for
  `terminal-notifier`. Focus modes suppress banners unless you allow that app in
  the Focus settings.
