// Native macOS agent that notifies when a YubiKey is waiting for a touch.
//
// Detection uses two native macOS signals —
//   FIDO2/U2F  CTAPHID KEEPALIVE reports that request user presence
//   OpenPGP    the system CCID reader emits "Time extension received"
//
// The banner subtitle names the waiting process: the HID user client creator
// for FIDO2, the gpg-agent socket client for OpenPGP.
//
// Notifications come from this signed bundle, so the banner shows this app's
// icon and the system attributes the login item to it.

import AppKit
import Foundation
import IOKit.hid
import ServiceManagement
import UserNotifications

let groupID = "yk-touch"

let pgpPredicate =
    #"(processImagePath == "/System/Library/CryptoTokenKit/usbsmartcardreaderd.slotd/Contents/MacOS/usbsmartcardreaderd" AND subsystem == "com.apple.CryptoTokenKit" AND category == "ccid")"#

let pgpRestartDelay: TimeInterval = 5
let fidoIdleTimeout: TimeInterval = 2
let fidoUsagePage = 0xf1d0
let ctaphidKeepalive: UInt8 = 0xbb
let ctaphidUpNeeded: UInt8 = 0x02
let maxFIDOChannels = 64

let agents = [
    "claude": "Claude Code",
    "codex": "Codex",
    "gemini": "Gemini CLI",
    "copilot": "Copilot CLI",
    "cursor-agent": "Cursor",
    "Cursor": "Cursor",
    "Windsurf": "Windsurf",
    "opencode": "OpenCode",
    "aider": "Aider",
    "amp": "Amp",
    "goose": "Goose",
    "droid": "Droid",
    "qwen": "Qwen Code",
]
let interpreters: Set = ["node", "bun", "deno"]

struct FIDOEvent: Equatable {
    let channel: UInt32
    let needsTouch: Bool
}

func parseFIDOReport(_ report: UnsafeBufferPointer<UInt8>) -> FIDOEvent? {
    guard report.count >= 7, report[4] & 0x80 != 0 else { return nil }
    let channel =
        UInt32(report[0]) << 24 | UInt32(report[1]) << 16
        | UInt32(report[2]) << 8 | UInt32(report[3])

    guard report[4] == ctaphidKeepalive else {
        return FIDOEvent(channel: channel, needsTouch: false)
    }
    guard report.count >= 8, report[5] == 0, report[6] == 1 else { return nil }
    switch report[7] {
    case ctaphidUpNeeded: return FIDOEvent(channel: channel, needsTouch: true)
    case 0x01: return FIDOEvent(channel: channel, needsTouch: false)
    default: return nil
    }
}

func isPGPExtension(_ line: String) -> Bool {
    line.hasSuffix("[com.apple.CryptoTokenKit:ccid] Time extension received")
}

struct FIDOChannel: Hashable {
    let deviceID: ObjectIdentifier
    let channel: UInt32
}

struct TouchState {
    var fidoWaiting = [FIDOChannel: UInt64]()
    var fidoGeneration: UInt64 = 0
    var pgpActive = false

    var notificationKind: String? {
        switch (!fidoWaiting.isEmpty, pgpActive) {
        case (true, true): "FIDO2 + OpenPGP"
        case (true, false): "FIDO2"
        case (false, true): "OpenPGP"
        case (false, false): nil
        }
    }

    @discardableResult mutating func handleFIDO(
        _ event: FIDOEvent, deviceID: ObjectIdentifier
    ) -> (key: FIDOChannel, generation: UInt64)? {
        let key = FIDOChannel(deviceID: deviceID, channel: event.channel)
        if event.needsTouch {
            guard fidoWaiting[key] != nil || fidoWaiting.count < maxFIDOChannels else { return nil }
            fidoGeneration += 1
            fidoWaiting[key] = fidoGeneration
            return (key, fidoGeneration)
        } else {
            fidoWaiting.removeValue(forKey: key)
            return nil
        }
    }

    mutating func expireFIDO(_ key: FIDOChannel, generation: UInt64) {
        guard fidoWaiting[key] == generation else { return }
        fidoWaiting.removeValue(forKey: key)
    }

    mutating func removeFIDODevice(_ deviceID: ObjectIdentifier) {
        fidoWaiting = fidoWaiting.filter { $0.key.deviceID != deviceID }
    }
}

func cString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}

func creatorPID(_ creator: String) -> pid_t? {
    guard creator.hasPrefix("pid ") else { return nil }
    return pid_t(creator.dropFirst(4).prefix { $0.isNumber })
}

func agentName(executable: String, argv: [String]) -> String? {
    let names = argv.prefix(2).map { ($0 as NSString).lastPathComponent }
    let interpreted = names.first.map { interpreters.contains($0) || $0.hasPrefix("python") } ?? false
    let app = executable.split(separator: "/").first { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
    return (names.prefix(interpreted ? 2 : 1) + [app].compactMap { $0 }).lazy.compactMap { agents[$0] }.first
}

func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
}

func processArgs(_ pid: pid_t) -> (executable: String, argv: [String])? {
    var mib = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return nil }
    let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
    let strings = buf[4..<size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    guard let executable = strings.first else { return nil }
    return (executable, Array(strings.dropFirst().prefix(Int(argc))))
}

func describeRequester(_ pids: [pid_t]) -> String? {
    let started = pids.compactMap { pid in bsdInfo(pid).map { (pid, $0.pbi_start_tvsec, $0.pbi_start_tvusec) } }
    guard var pid = started.max(by: { ($0.1, $0.2) < ($1.1, $1.2) })?.0 else { return nil }
    var chain = [String]()
    var agent: String?
    while pid > 1, let info = bsdInfo(pid) {
        if chain.count < 2 { chain.append(cString(info.pbi_name)) }
        if agent == nil, let args = processArgs(pid) { agent = agentName(executable: args.executable, argv: args.argv) }
        pid = pid_t(info.pbi_ppid)
    }
    guard !chain.isEmpty else { return nil }
    let path = chain.joined(separator: " ← ")
    return agent.map { "\($0): \(path)" } ?? path
}

func fidoClientPIDs(_ device: IOHIDDevice) -> [pid_t] {
    var iterator = io_iterator_t()
    guard IORegistryEntryGetChildIterator(IOHIDDeviceGetService(device), kIOServicePlane, &iterator) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var pids = [pid_t]()
    var child = IOIteratorNext(iterator)
    while child != 0 {
        if let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, nil, 0)?
            .takeRetainedValue() as? String, let pid = creatorPID(creator), pid != getpid()
        {
            pids.append(pid)
        }
        IOObjectRelease(child)
        child = IOIteratorNext(iterator)
    }
    return pids
}

func hasGPGAgentConnection(_ pid: pid_t) -> Bool {
    let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard size > 0 else { return false }
    var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.stride)
    let filled = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)) / MemoryLayout<proc_fdinfo>.stride
    return fds.prefix(filled).contains { fd in
        var info = socket_fdinfo()
        let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
        guard fd.proc_fdtype == PROX_FDTYPE_SOCKET,
            proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
            info.psi.soi_family == AF_UNIX
        else { return false }
        return cString(info.psi.soi_proto.pri_un.unsi_caddr.ua_sun.sun_path).contains("/S.gpg-agent")
    }
}

func gpgAgentClientPIDs() -> [pid_t] {
    let uid = getuid()
    let size = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
    var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.stride)
    let count = Int(proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, size)) / MemoryLayout<pid_t>.stride
    return pids.prefix(count).filter { $0 > 0 && hasGPGAgentConnection($0) }
}

func selfCheck() {
    let keepalive = [0x72, 0xa9, 0x28, 0x70, 0xbb, 0x00, 0x01, 0x02] as [UInt8]
    let processing = [0x72, 0xa9, 0x28, 0x70, 0xbb, 0x00, 0x01, 0x01] as [UInt8]
    let completed = [0x72, 0xa9, 0x28, 0x70, 0x90, 0x00, 0x01, 0x2e] as [UInt8]
    let continuation = [0x72, 0xa9, 0x28, 0x70, 0x00, 0x00, 0x00, 0x00] as [UInt8]
    let up = keepalive.withUnsafeBufferPointer { parseFIDOReport($0) }
    let done = completed.withUnsafeBufferPointer { parseFIDOReport($0) }
    precondition(up == FIDOEvent(channel: 0x72a92870, needsTouch: true))
    precondition(processing.withUnsafeBufferPointer { parseFIDOReport($0) }?.needsTouch == false)
    precondition(done == FIDOEvent(channel: 0x72a92870, needsTouch: false))
    precondition(continuation.withUnsafeBufferPointer { parseFIDOReport($0) } == nil)
    precondition(!isPGPExtension(#"Filtering using eventMessage == "Time extension received""#))
    let pgpExtension =
        "usbsmartcardreaderd[1:2] [com.apple.CryptoTokenKit:ccid] Time extension received"
    precondition(isPGPExtension(pgpExtension))

    let firstDevice = NSObject()
    let secondDevice = NSObject()
    let firstID = ObjectIdentifier(firstDevice)
    let secondID = ObjectIdentifier(secondDevice)
    var state = TouchState()
    let stale = state.handleFIDO(up!, deviceID: firstID)!
    let current = state.handleFIDO(up!, deviceID: firstID)!
    state.expireFIDO(stale.key, generation: stale.generation)
    state.handleFIDO(FIDOEvent(channel: 7, needsTouch: true), deviceID: secondID)
    state.handleFIDO(done!, deviceID: firstID)
    precondition(state.notificationKind == "FIDO2")
    state.expireFIDO(current.key, generation: current.generation)
    state.removeFIDODevice(secondID)
    precondition(state.notificationKind == nil)

    let timeout = state.handleFIDO(up!, deviceID: firstID)!
    state.expireFIDO(timeout.key, generation: timeout.generation)
    precondition(state.notificationKind == nil)

    state.pgpActive = isPGPExtension(pgpExtension)
    precondition(state.notificationKind == "OpenPGP")
    state.handleFIDO(up!, deviceID: firstID)
    precondition(state.notificationKind == "FIDO2 + OpenPGP")
    state.handleFIDO(done!, deviceID: firstID)
    precondition(state.notificationKind == "OpenPGP")
    state.pgpActive = isPGPExtension(
        "usbsmartcardreaderd[1:2] [com.apple.CryptoTokenKit:ccid] Card response received")
    precondition(state.notificationKind == nil)

    precondition(creatorPID("pid 1742, yubikey-touch-no") == 1742)
    precondition(agentName(executable: "/opt/homebrew/bin/node", argv: ["node", "/opt/homebrew/bin/gemini"]) == "Gemini CLI")
    precondition(
        agentName(
            executable: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)",
            argv: []) == "Cursor")
    precondition(agentName(executable: "/bin/zsh", argv: ["-zsh"]) == nil)
    precondition(agentName(executable: "/usr/bin/ssh", argv: ["ssh", "claude"]) == nil)
}

let fidoReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, count in
    guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput, reportID == 0,
        count >= 7, let context, let sender
    else { return }
    guard let event = parseFIDOReport(UnsafeBufferPointer(start: report, count: min(count, 8))) else { return }
    let notifier = Unmanaged<Notifier>.fromOpaque(context).takeUnretainedValue()
    let device = unsafeBitCast(sender, to: IOHIDDevice.self)
    notifier.handleFIDO(event, deviceID: ObjectIdentifier(device))
}

let fidoDeviceMatched: IOHIDDeviceCallback = { context, result, _, device in
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<Notifier>.fromOpaque(context).takeUnretainedValue().addFIDODevice(device)
}

let fidoDeviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<Notifier>.fromOpaque(context).takeUnretainedValue().removeFIDODevice(device)
}

final class Notifier: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    var state = TouchState()
    var displayedKind: String?
    var logProcess: Process?
    var hidManager: IOHIDManager?
    var fidoDevices = [ObjectIdentifier: IOHIDDevice]()
    let testMode = CommandLine.arguments.contains("--test")

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        dismiss()

        if testMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.post("Test") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
            return
        }
        try? SMAppService.mainApp.register()
        startFIDO()
        streamPGP()
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
        c.subtitle = requester() ?? ""
        c.body = "Touch your YubiKey"
        c.sound = .default
        // Fixed identifier so a later add replaces, and dismiss can remove it.
        center.add(UNNotificationRequest(identifier: groupID, content: c, trigger: nil))
    }

    func requester() -> String? {
        var pids = state.fidoWaiting.keys.compactMap { fidoDevices[$0.deviceID] }.flatMap(fidoClientPIDs)
        if state.pgpActive { pids += gpgAgentClientPIDs() }
        return describeRequester(pids)
    }

    func dismiss() {
        center.removePendingNotificationRequests(withIdentifiers: [groupID])
        center.removeDeliveredNotifications(withIdentifiers: [groupID])
    }

    func refreshNotification() {
        let kind = state.notificationKind
        guard kind != displayedKind else { return }
        displayedKind = kind
        if let kind { post(kind) } else { dismiss() }
    }

    func startFIDO() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x1050,
            kIOHIDDeviceUsagePageKey as String: fidoUsagePage,
            kIOHIDDeviceUsageKey as String: 1,
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, fidoDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, fidoDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, fidoReportCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            NSLog("yubikey-touch-notifier: FIDO monitor failed to start: \(result)")
            return
        }
        hidManager = manager
    }

    func addFIDODevice(_ device: IOHIDDevice) {
        fidoDevices[ObjectIdentifier(device)] = device
    }

    func removeFIDODevice(_ device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        guard fidoDevices.removeValue(forKey: key) != nil else { return }
        state.removeFIDODevice(key)
        refreshNotification()
    }

    func handleFIDO(_ event: FIDOEvent, deviceID: ObjectIdentifier) {
        guard fidoDevices[deviceID] != nil else { return }
        let expiry = state.handleFIDO(event, deviceID: deviceID)
        refreshNotification()
        if let expiry {
            DispatchQueue.main.asyncAfter(deadline: .now() + fidoIdleTimeout) {
                self.state.expireFIDO(expiry.key, generation: expiry.generation)
                self.refreshNotification()
            }
        }
    }

    func schedulePGPRestart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + pgpRestartDelay) {
            self.streamPGP()
        }
    }

    func streamPGP() {
        guard logProcess == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--level", "debug", "--style", "compact", "--predicate", pgpPredicate]
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
                    DispatchQueue.main.async {
                        guard self.logProcess === p else { return }
                        self.handlePGP(line)
                    }
                }
            }
        }
        p.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.logProcess === process else { return }
                self.logProcess = nil
                self.state.pgpActive = false
                self.refreshNotification()
                NSLog(
                    "yubikey-touch-notifier: log stream exited with status "
                        + "\(process.terminationStatus); restarting")
                self.schedulePGPRestart()
            }
        }
        do {
            try p.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            NSLog("yubikey-touch-notifier: log stream failed to start: \(error); restarting")
            schedulePGPRestart()
            return
        }
        logProcess = p
    }

    func handlePGP(_ line: String) {
        state.pgpActive = isPGPExtension(line)
        refreshNotification()
    }
}

if CommandLine.arguments.contains("--self-check") {
    selfCheck()
    print("self-check passed")
    exit(0)
}

if CommandLine.arguments.contains("--uninstall") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = Notifier()
app.delegate = delegate
app.run()
