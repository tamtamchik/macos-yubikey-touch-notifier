<img alt="image" src="https://github.com/user-attachments/assets/55cb1b65-72d5-4ea7-9385-e35c408b0f05" />

# macOS Yubikey Touch Notifier

macOS notification when your YubiKey is waiting for a touch.

> [!IMPORTANT]
> Requires **macOS 26.0 or later** on **Apple Silicon**. Intel Macs are not supported.

Two native signals are matched:

- **FIDO2 / U2F**: the YubiKey sends a CTAPHID `KEEPALIVE` report requesting user presence.
- **OpenPGP**: the smartcard stack (`CryptoTokenKit`) emits `Time extension received`.

A banner appears while the key is waiting and withdraws when the operation ends.

## Install

1. Download `YubiKeyTouchNotifier.zip` from the
[latest release](https://github.com/tamtamchik/macos-yubikey-touch-notifier/releases/latest)
2. Unzip it
3. Move **YubiKey Touch Notifier.app** to `/Applications`.
4. Open it once.

> [!NOTE]
> macOS asks to allow notifications, and the app registers itself as a login item so it starts automatically afterwards.
> The release download is signed and notarized, so it should open without a Gatekeeper warning.

The legacy shell scripts remain in the repository for historical reference.
They are unsupported and do not include the macOS 26 signal handling.

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

The build requires Xcode 26 and produces an arm64 app for macOS 26.0 or later.
Intel Macs are not supported.

```sh
./app/build.sh      # builds YubiKey Touch Notifier.app into ./build
```

## Notes

- OpenPGP detection is heuristic and may break if a future macOS release renames
  its CryptoTokenKit log message.
- Focus modes suppress banners unless you allow the app in the Focus settings.
