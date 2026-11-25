import AppKit

/// TEMP debug logging to a file, so logs are readable no matter how the app is launched.
func blog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    NSLog("[Basilisk] \(message)")
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/basilisk_debug.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Software (app-side) button actions
//
// These are the Mac-Mouse-Fix–style actions macOS has no storable keystroke for
// (Mission Control, Launchpad, …) or no shortcut at all (gestures). The mouse can't
// perform them on its own, so the app does, at runtime, while it is running.
//
// How a button reaches us: assigning a software action writes a *sentinel* mouse-button
// number to the mouse's firmware (an otherwise-unused HID button usage). A CGEventTap
// then recognises that button number, swallows the click so nothing stray leaks, and
// runs the action. The sentinel is unique to us, so we never confuse it with a real
// click on this or any other mouse.

/// A runtime action performed by the app rather than stored on the mouse.
enum SoftwareAction: String, CaseIterable, Identifiable, Codable {
    // Phase A — robust (CoreDock / posted keystrokes)
    case missionControl, appExpose, showDesktop, launchpad, spaceLeft, spaceRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose:      "App Exposé"
        case .showDesktop:    "Show Desktop"
        case .launchpad:      "Launchpad"
        case .spaceLeft:      "Move Left a Space"
        case .spaceRight:     "Move Right a Space"
        }
    }
}

/// One button's binding to a software action, remembered across launches.
private struct SentinelBinding: Codable {
    var sentinel: UInt8
    var action: SoftwareAction
}

/// Owns the event tap and the sentinel bookkeeping. Singleton, main-actor: the tap is
/// scheduled on the main run loop so its callback can touch this state directly.
@MainActor
final class GestureEngine {
    static let shared = GestureEngine()

    // Sentinel = a rare key combo the firmware emits reliably (the mouse can't emit
    // exotic button numbers — those collapse to a left click). We use Hyper (⌃⌥⇧⌘) plus
    // an F13–F20 key: no app binds those, and we swallow them so they never leak.
    static let hyperModifiers: UInt8 = 0x0F               // ⌃⌥⇧⌘ in firmware bit order
    /// Firmware key usages used as sentinels (F13–F20).
    private static let sentinelPool: [UInt8] = [0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F]
    /// Firmware usage → macOS virtual key code, for matching tapped key events.
    private static let keyCodeForUsage: [UInt8: Int64] =
        [0x68: 105, 0x69: 107, 0x6A: 113, 0x6B: 106, 0x6C: 64, 0x6D: 79, 0x6E: 80, 0x6F: 90]
    private static let requiredFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    private static let storeKey = "softwareButtonBindings"

    /// "profile-buttonRaw" → binding. The source of truth; persisted as JSON.
    private var byButton: [String: SentinelBinding] = [:]
    /// Derived: sentinel firmware usage → action, for the hot path in the tap callback.
    private var actionBySentinel: [UInt8: SoftwareAction] = [:]
    /// Key codes whose `down` we consumed, so we also consume the matching `up`.
    private var suppressing: Set<Int64> = []

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    /// Verbose logging of raw button numbers — used to confirm the mouse emits sentinels.
    var debugLogging = false

    private init() { load() }

    // MARK: Lifecycle

    /// Installs the tap if Accessibility is granted and it isn't already running.
    /// Returns whether the tap is active afterwards. Safe to call repeatedly.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let trusted = AXIsProcessTrusted()
        if debugLogging { blog("start trusted=\(trusted)") }
        guard trusted else {
            scheduleRetry()   // keep polling so granting access takes effect without relaunch
            return false
        }
        retryTimer?.invalidate(); retryTimer = nil

        let functional: UInt64 = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        // Diagnostic: also watch mouse/flags/systemDefined so we can see what each button emits.
        let diagnostic: UInt64 = functional | (1<<1) | (1<<3) | (1<<12) | (1<<14) | (1<<25) | (1<<26)
        let mask = debugLogging ? diagnostic : functional
        let callback: CGEventTapCallBack = { _, type, event, _ in
            MainActor.assumeIsolated { GestureEngine.shared.handle(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        if debugLogging { blog("tap installed") }
        return true
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { _ = GestureEngine.shared.start() }
        }
    }

    /// Opens the Accessibility pane and prompts for access if not already granted.
    func requestAccessIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if debugLogging {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            blog("evt type=\(type.rawValue) button=\(button) keycode=\(keycode) flags=\(event.flags.rawValue)")
        }

        switch type {
        case .keyDown:
            // Must carry all of Hyper, and be one of our sentinel F-keys.
            guard event.flags.isSuperset(of: Self.requiredFlags),
                  let usage = Self.usage(forKeyCode: keycode),
                  let action = actionBySentinel[usage] else { break }
            suppressing.insert(keycode)
            perform(action)
            return nil   // swallow so the sentinel combo never reaches any app
        case .keyUp:
            if suppressing.remove(keycode) != nil { return nil }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Bindings

    private func key(_ button: MouseButton, _ profile: UInt8) -> String { "\(profile)-\(button.rawValue)" }

    /// Binds a button (in a profile) to a software action and returns the sentinel usage
    /// to write to firmware. Reuses the button's existing sentinel if it had one.
    func bind(_ action: SoftwareAction, button: MouseButton, profile: UInt8) -> UInt8 {
        let k = key(button, profile)
        let reuse = byButton[k]?.sentinel
        let sentinel = (reuse != nil && Self.sentinelPool.contains(reuse!)) ? reuse! : firstFreeSentinel()
        byButton[k] = SentinelBinding(sentinel: sentinel, action: action)
        reindex(); save()
        start()   // in case Accessibility was granted after launch
        return sentinel
    }

    /// Clears a button's software binding unless `firmwareAction` is still its sentinel combo.
    func noteFirmwareAssignment(button: MouseButton, profile: UInt8, action firmwareAction: ButtonAction) {
        let k = key(button, profile)
        guard let b = byButton[k] else { return }
        if case .key(let m, let u) = firmwareAction, m == Self.hyperModifiers, u == b.sentinel { return }
        byButton[k] = nil
        reindex(); save()
    }

    /// The software action bound to a sentinel firmware key usage, if any.
    func action(forSentinel usage: UInt8) -> SoftwareAction? { actionBySentinel[usage] }

    /// Our sentinel firmware usage for a tapped macOS key code, if it is one.
    static func usage(forKeyCode code: Int64) -> UInt8? {
        keyCodeForUsage.first { $0.value == code }?.key
    }

    private func firstFreeSentinel() -> UInt8 {
        let used = Set(byButton.values.map(\.sentinel))
        return Self.sentinelPool.first { !used.contains($0) } ?? Self.sentinelPool[0]
    }

    private func reindex() {
        actionBySentinel = Dictionary(byButton.values.map { ($0.sentinel, $0.action) },
                                      uniquingKeysWith: { a, _ in a })
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: SentinelBinding].self, from: data) {
            byButton = decoded
        }
        reindex()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(byButton) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    // MARK: Execution

    /// Private Dock entry point macOS itself uses for these; resolved at runtime.
    private lazy var coreDockSend: (@convention(c) (CFString, Int32) -> Void)? = {
        let paths = [
            nil,  // already-loaded images (HIServices may export it)
            "/System/Library/PrivateFrameworks/CoreDockAPI.framework/CoreDockAPI",
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        ]
        for p in paths {
            guard let h = dlopen(p, RTLD_NOW) else { continue }
            if let sym = dlsym(h, "CoreDockSendNotification") {
                return unsafeBitCast(sym, to: (@convention(c) (CFString, Int32) -> Void).self)
            }
        }
        return nil
    }()

    private func perform(_ action: SoftwareAction) {
        switch action {
        case .missionControl:
            if let send = coreDockSend { send("com.apple.expose.awake" as CFString, 0) }
            else { postKey(126, flags: .maskControl) }                 // ⌃↑
        case .appExpose:
            if let send = coreDockSend { send("com.apple.expose.front.awake" as CFString, 0) }
            else { postKey(125, flags: .maskControl) }                 // ⌃↓
        case .showDesktop:
            if let send = coreDockSend { send("com.apple.showdesktop.awake" as CFString, 0) }
        case .launchpad:
            if let send = coreDockSend { send("com.apple.launchpad.toggle" as CFString, 0) }
        case .spaceLeft:  postKey(123, flags: .maskControl)            // ⌃←
        case .spaceRight: postKey(124, flags: .maskControl)            // ⌃→
        }
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}
