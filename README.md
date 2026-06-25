<img alt="image" src="https://github.com/user-attachments/assets/cfd44ae2-5aa1-4b03-873d-b18ad88917f5" />

# macOS Yubikey Touch Notifier

macOS notification when your YubiKey is waiting for a touch.

The signal is the unified log. Two cases are matched:

- **FIDO2 / U2F**: a client that opened the YubiKey HID device calls `startQueue`.
- **OpenPGP**: the smartcard stack (`CryptoTokenKit`) emits `Time extension received`.

State is edge-triggered: a banner appears when a touch starts and withdraws once
you touch the key.

## Install

Download `YubiKeyTouchNotifier.zip` from the
[latest release](https://github.com/tamtamchik/macos-yubikey-touch-notifier/releases/latest),
unzip it, and move **YubiKey Touch Notifier.app** to `/Applications`.

Open it once. macOS asks to allow notifications, and the app registers itself as
a login item so it starts automatically afterwards. No Homebrew, no
`terminal-notifier`, no `sudo`. The release download is signed and notarized, so
it opens without a Gatekeeper warning.

Notifications come from the app's own signed bundle, so the banner shows its
YubiKey icon instead of Terminal's.

<details>
<summary>Legacy: shell script + terminal-notifier</summary>

A single shell script over `log` + `awk` +
[`terminal-notifier`](https://github.com/julienXX/terminal-notifier). Same
detection, delivered through `terminal-notifier` and a launchd agent.

```sh
curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/install.sh | bash
```

Needs [Homebrew](https://brew.sh) (for `terminal-notifier`) and asks for `sudo`
to write into `/usr/local`.

Manual install:

```sh
brew install terminal-notifier

sudo install -m 755 yubikey-touch-notifier /usr/local/bin/yubikey-touch-notifier
sudo install -d /usr/local/share/yubikey-touch-notifier
sudo install -m 644 icon.png /usr/local/share/yubikey-touch-notifier/icon.png

cp com.tamtamchik.yubikey-touch-notifier.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.tamtamchik.yubikey-touch-notifier.plist
```

Run it in the foreground with `./yubikey-touch-notifier`. `YK_SOUND` sets the
notification sound (default `Submarine`); `YK_SOUND=` mutes it. `YK_ICON`
overrides the banner icon path.

Uninstall:

```sh
curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/uninstall.sh | bash
```

</details>

## Test it

Perform a touch-required operation: a GPG signature (`echo test | gpg
--clearsign`), an SSH auth, or a WebAuthn login. A "Touch your YubiKey"
notification appears. (`gpg --card-status` does **not** request a touch, so it
will not trigger one.)

To post a sample banner without a real touch:

```sh
"/Applications/YubiKey Touch Notifier.app/Contents/MacOS/yubikey-touch-notifier" --test
```

## Uninstall

```sh
"/Applications/YubiKey Touch Notifier.app/Contents/MacOS/yubikey-touch-notifier" --uninstall
```

This deregisters the login item. Then drag the app to the Trash.

## Build from source

```sh
./app/build.sh      # builds YubiKey Touch Notifier.app into ./build
```

## Notes

- Detection is heuristic, based on log messages, and may break on a future macOS
  release that renames them.
- Focus modes suppress banners unless you allow the app in the Focus settings.
