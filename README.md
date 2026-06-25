<img alt="image" src="https://github.com/user-attachments/assets/cfd44ae2-5aa1-4b03-873d-b18ad88917f5" />

# macOS Yubikey Touch Notifier

macOS notification when your YubiKey is waiting for a touch.

The signal is the unified log. Two cases are matched:

- **FIDO2 / U2F**: a client that opened the YubiKey HID device calls `startQueue`.
- **OpenPGP**: the smartcard stack (`CryptoTokenKit`) emits `Time extension received`.

State is edge-triggered: a banner appears when a touch starts and withdraws once
you touch the key.

## Install

1. Download `YubiKeyTouchNotifier.zip` from the
[latest release](https://github.com/tamtamchik/macos-yubikey-touch-notifier/releases/latest)
2. Unzip it
3. Move **YubiKey Touch Notifier.app** to `/Applications`.
4. Open it once.

> [!NOTE]
> macOS asks to allow notifications, and the app registers itself as a login item so it starts automatically afterwards.
> The release download is signed and notarized, so it should open without a Gatekeeper warning.

<details>
<summary>Legacy: shell script + terminal-notifier install instructions</summary>

Install:

```sh
curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/install.sh | bash
```

Manual install:

```sh
brew install terminal-notifier

sudo install -m 755 yubikey-touch-notifier /usr/local/bin/yubikey-touch-notifier
sudo install -d /usr/local/share/yubikey-touch-notifier
sudo install -m 644 icon.png /usr/local/share/yubikey-touch-notifier/icon.png

cp com.tamtamchik.yubikey-touch-notifier.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.tamtamchik.yubikey-touch-notifier.plist
```

Uninstall:

```sh
curl -fsSL https://raw.githubusercontent.com/tamtamchik/macos-yubikey-touch-notifier/main/uninstall.sh | bash
```

</details>

## Test it

Perform a touch-required operation: a GPG signature (`echo test | gpg --clearsign`), an SSH auth, or a WebAuthn login. 
A "Touch your YubiKey" notification appears.

To trigger a sample banner without a real touch:

```sh
"/Applications/YubiKey Touch Notifier.app/Contents/MacOS/yubikey-touch-notifier" --test
```

## Uninstall

```sh
"/Applications/YubiKey Touch Notifier.app/Contents/MacOS/yubikey-touch-notifier" --uninstall
pkill -f "YubiKey Touch Notifier.app"
```

- `--uninstall` deregisters the login item; 
- `pkill` stops the running agent (the Finder refuses to trash it while it is open).

Then drag the app to the Trash.

## Build from source

```sh
./app/build.sh      # builds YubiKey Touch Notifier.app into ./build
```

## Notes

- Detection is heuristic, based on log messages, and may break on a future macOS
  release that renames them.
- Focus modes suppress banners unless you allow the app in the Focus settings.
