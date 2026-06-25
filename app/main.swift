// Native macOS agent that notifies when a YubiKey is waiting for a touch.
//
// Detection mirrors the original shell tool: it streams the macOS unified log
// and matches two cases —
//   FIDO2/U2F  a client that opened the YubiKey HID device calls startQueue
//   OpenPGP    CryptoTokenKit emits "Time extension received"
// State is edge-triggered: notify once when a touch starts, withdraw when done.
//
// Unlike terminal-notifier, notifications come from THIS signed bundle, so the
// banner shows this app's icon (not Terminal's) and the system attributes the
// login item to it.

import AppKit
import Foundation
import ServiceManagement
import UserNotifications

let groupID = "yk-touch"

let predicate =
    #"(processImagePath == "/kernel" AND senderImagePath ENDSWITH "IOHIDFamily") OR (subsystem CONTAINS "CryptoTokenKit")"#

// First capture group of the first match, or nil.
func capture(_ pattern: String, _ s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
        let g = Range(m.range(at: 1), in: s)
    else { return nil }
    return String(s[g])
}

final class Notifier: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    var ykdev = Set<String>()     // IORegistryEntryIDs of YubiKey HID devices
    var ykclient = Set<String>()  // IOHIDLibUserClient ids that opened one
    var fido = false
    var pgp = false
    var logProcess: Process?       // retained so the log stream outlives stream()
    let testMode = CommandLine.arguments.contains("--test")

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if testMode {
            // Clear any stale banner with our id first, else a re-add updates it silently.
            center.removeDeliveredNotifications(withIdentifiers: [groupID])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.post("Test") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
            return
        }
        try? SMAppService.mainApp.register()
        seed()
        stream()
    }

    // Show banners even though we run as a background agent.
    func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification,
        withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        done([.banner, .sound])
    }

    func post(_ kind: String) {
        let c = UNMutableNotificationContent()
        c.title = "YubiKey \(kind)"
        c.body = "Touch your YubiKey"
        c.sound = .default
        // Fixed identifier so a later add replaces, and dismiss can remove it.
        center.add(UNNotificationRequest(identifier: groupID, content: c, trigger: nil))
    }

    func dismiss() {
        center.removePendingNotificationRequests(withIdentifiers: [groupID])
        center.removeDeliveredNotifications(withIdentifiers: [groupID])
    }

    // YubiKeys (Yubico vendor 0x1050 = 4176) already attached before we start.
    // Live plug-ins are picked up from the log; pre-existing ones only from ioreg.
    func seed() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-r", "-c", "AppleUserUSBHostHIDDevice", "-d", "1"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return }
        var curID: String?
        for line in out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.contains("+-o ") { curID = capture(#"id (0x[0-9a-f]+)"#, line) }
            if line.contains("\"VendorID\" = 4176"), let id = curID { ykdev.insert(id) }
        }
    }

    func stream() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--level", "debug", "--style", "compact", "--predicate", predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        var buf = Data()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }  // EOF: stop the source
            buf.append(d)
            while let nl = buf.firstIndex(of: 0x0A) {
                let lineData = buf.subdata(in: buf.startIndex..<nl)
                buf.removeSubrange(buf.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) {
                    DispatchQueue.main.async { self.handle(line) }
                }
            }
        }
        do { try p.run() } catch { NSLog("yubikey-touch-notifier: log stream failed to start: \(error)"); return }
        logProcess = p
    }

    // Streaming state machine, one rule per line (mirrors the awk original).
    func handle(_ line: String) {
        // A YubiKey HID device registering -> remember its registry id.
        if line.contains("IORegistryEntryID"),
            line.contains(">Yubico<") || capture(#"(VendorID</key><integer[^>]*>0x1050<)"#, line) != nil
        {
            if let id = capture(#"IORegistryEntryID</key><integer[^>]*>([^<]+)<"#, line) { ykdev.insert(id) }
            return
        }
        // Client that opened a YubiKey HID device (ignore other devices).
        if line.contains(" open by IOHIDLibUserClient:"),
            let dev = capture(#"AppleUserUSBHostHIDDevice:(0x[0-9a-f]+) open by"#, line),
            let cli = capture(#"open by IOHIDLibUserClient:(0x[0-9a-f]+)"#, line)
        {
            if ykdev.contains(dev) { ykclient.insert(cli) }
            return
        }
        // FIDO2 touch begins / ends for one of those clients.
        if let cli = capture(#"IOHIDLibUserClient:(0x[0-9a-f]+) startQueue"#, line) {
            if ykclient.contains(cli), !fido { post("FIDO2"); fido = true }
            return
        }
        if let cli = capture(#"IOHIDLibUserClient:(0x[0-9a-f]+) stopQueue"#, line) {
            if ykclient.contains(cli), fido { dismiss(); fido = false }
            return
        }
        // OpenPGP: scdaemon keeps the card busy -> repeated time extensions.
        // Any other CryptoTokenKit line means the card answered -> touch done.
        if line.contains("CryptoTokenKit") {
            if line.contains("Time extension received") {
                if !pgp { post("OpenPGP"); pgp = true }
            } else if pgp {
                dismiss()
                pgp = false
            }
        }
    }
}

if CommandLine.arguments.contains("--uninstall") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = Notifier()
app.delegate = delegate
app.run()
