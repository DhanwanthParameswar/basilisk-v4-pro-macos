import Foundation
import IOKit.hid
import Observation
import SwiftUI

/// Single source of truth for the app.
///
/// * Discovers the mouse with an IOHIDManager (hot-plug callbacks, no polling) and falls back to
///   Bluetooth when no USB link answers. Preference: wired > HyperSpeed dongle > Bluetooth.
/// * Reads the device state once on connect, then only refreshes the cheap "live" values
///   (battery, active DPI stage) — every few seconds while the window is visible, once a minute otherwise.
/// * Writes are optimistic: the UI updates immediately, the command is sent, and the previous value
///   is restored if the mouse rejects it.
@MainActor
@Observable
final class DeviceManager {
    enum Connection: Equatable {
        case searching
        case connected(TransportKind)
        case unreachable(String)
    }

    // Connection
    private(set) var connection: Connection = .searching
    private(set) var isLoading = false
    var lastError: String?

    // Identity
    private(set) var firmware: String?
    private(set) var serial: String?

    // Performance
    var stages: [DPIStage] = DPI.presets.map { DPIStage(x: $0, y: $0) }
    var activeStage = 2
    var pollingRate: PollingRate = .hz1000
    var smartTracking: SmartTracking = .medium

    // Scroll wheel
    var scrollMode: ScrollMode = .tactile
    var disabledModes: Set<ScrollMode> = []
    var scrollAcceleration = false
    var accelerationLevel = 2
    var smartReel = false
    var smartReelLevel = 2

    // Lighting
    var brightness: Double = 0.6
    var effects: [LightingZone: LightingEffect] = Dictionary(uniqueKeysWithValues: LightingZone.allCases.map { ($0, LightingEffect()) })
    var smartDimming = true
    var smartDimPercent = 25

    // Power
    private(set) var battery: Int?
    private(set) var charging = false
    var sleepMinutes = 5
    var lowPowerPercent = 30

    // Buttons
    var assignments: [MouseButton: ButtonAction] = [:]

    // Onboard memory. Per-profile settings (DPI, polling, scroll wheel, brightness, buttons) are
    // read from and written to the active profile, so the app always edits what the mouse is using.
    private(set) var profiles: [OnboardProfile] = []
    private(set) var activeProfile: UInt8 = V4Pro.store
    private(set) var storage: OnboardStorage?
    private(set) var profileBusy = false

    // Background
    var windowVisible = false { didSet { rescheduleLiveRefresh() } }

    private var transport: RazerTransport?
    private var hidManager: IOHIDManager?
    private var hidCandidates: [IOHIDDevice] = []
    private var ble: BLETransport?
    private var liveTimer: Timer?
    private var bleFallbackTask: Task<Void, Never>?
    private var dongleRetryTask: Task<Void, Never>?

    var kind: TransportKind? {
        if case .connected(let k) = connection { return k }
        return nil
    }
    var isConnected: Bool { kind != nil }
    var activeDPI: Int { stages.indices.contains(activeStage) ? stages[activeStage].x : 0 }

    func supports(_ cls: UInt8) -> Bool { transport?.supports(cls) ?? false }
    var supportsFullControl: Bool { supports(0x04) }

    // MARK: - Lifecycle

    func start() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Match only the vendor control interface (primary usage 0x0C/0x01, 90-byte feature report).
        // Never open the keyboard-type interfaces — that would trigger the Input Monitoring prompt.
        let matches: [[String: Any]] = [0x00E2, 0x00E3].map {
            [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: $0,
             kIOHIDPrimaryUsagePageKey: 0x0C, kIOHIDPrimaryUsageKey: 0x01]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            let me = Unmanaged<DeviceManager>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.hidDeviceAppeared(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            let me = Unmanaged<DeviceManager>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.hidDeviceRemoved(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager
        scheduleBluetoothFallback(after: 1.5)
    }

    // MARK: - Discovery

    private func isControlInterface(_ d: IOHIDDevice) -> Bool {
        (IOHIDDeviceGetProperty(d, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int) == RazerPacket.length
    }

    private func hidDeviceAppeared(_ device: IOHIDDevice) {
        guard isControlInterface(device) else { return }
        hidCandidates.append(device)
        Task { await evaluateHIDCandidates() }
    }

    private func hidDeviceRemoved(_ device: IOHIDDevice) {
        hidCandidates.removeAll { $0 == device }
        if let t = transport as? HIDTransport, t.device == device {
            t.close()
            transport = nil
            connection = .searching
            Task { await evaluateHIDCandidates() }
            scheduleBluetoothFallback(after: 0.5)
        }
    }

    private func pid(_ d: IOHIDDevice) -> Int { IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0 }

    /// Try wired first, then the dongle. A dongle whose mouse is off/asleep/on Bluetooth enumerates
    /// but never answers — probe it before adopting it.
    private func evaluateHIDCandidates() async {
        if let current = transport, current.kind == .usb { return }
        let ordered = hidCandidates.sorted { pid($0) < pid($1) }   // 0x00E2 (wired) before 0x00E3 (dongle)
        for device in ordered {
            if let t = transport as? HIDTransport, t.device == device { return }
            let kind: TransportKind = pid(device) == 0x00E2 ? .usb : .dongle
            if let current = transport, current.kind == .dongle, kind == .dongle { return }
            let candidate = HIDTransport(device: device, kind: kind)
            if (try? await candidate.send(V4Pro.firmware)) != nil {
                adopt(candidate)
                return
            }
            candidate.close()
            if kind == .dongle, transport == nil {
                connection = .unreachable("HyperSpeed dongle found, but the mouse isn't answering. Turn it on or switch it to 2.4 GHz.")
            }
            if kind == .dongle { scheduleDongleRetry() }
        }
    }

    /// The dongle stays enumerated while the mouse is off, asleep or on Bluetooth, so waking the
    /// mouse produces no hot-plug event. Re-probe with backoff until it answers or the dongle leaves.
    private func scheduleDongleRetry() {
        guard dongleRetryTask == nil else { return }
        dongleRetryTask = Task { [weak self] in
            var delay = 2.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                let onHID = self.transport.map { $0.kind != .bluetooth } ?? false
                if onHID || self.hidCandidates.isEmpty { break }
                await self.evaluateHIDCandidates()
                delay = min(delay * 1.5, self.transport?.kind == .bluetooth ? 30 : 10)
            }
            self?.dongleRetryTask = nil
        }
    }

    private func scheduleBluetoothFallback(after delay: Double) {
        bleFallbackTask?.cancel()
        bleFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.transport == nil else { return }
            if self.hidCandidates.isEmpty, Self.usbHeldByAnotherApp() {
                self.connection = .unreachable("The mouse is plugged in, but another app has taken it over — usually a Parallels or VMware virtual machine. Give the mouse back to macOS from the VM’s USB menu.")
            }
            self.startBluetooth()
        }
    }

    /// True when a Basilisk is on the USB bus but macOS has no HID interfaces for it, which means
    /// a VM (or another driver) has claimed the whole device.
    private static func usbHeldByAnotherApp() -> Bool {
        var iter: io_iterator_t = 0
        let match = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        match[kIOPropertyMatchKey] = ["idVendor": 0x1532]
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iter) }
        var found = false
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            if let pid = IORegistryEntryCreateCFProperty(s, "idProduct" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, [0x00E2, 0x00E3].contains(pid) { found = true }
        }
        return found
    }

    private func startBluetooth() {
        if ble == nil {
            let b = BLETransport()
            b.onReady = { [weak self] t in
                guard let self else { return }
                if self.transport == nil || self.transport?.kind == .bluetooth { self.adopt(t) }
            }
            b.onDisconnect = { [weak self] in
                guard let self, self.transport?.kind == .bluetooth else { return }
                self.transport = nil
                self.connection = .searching
            }
            b.onBattery = { [weak self] level in
                guard let self, self.transport?.kind == .bluetooth else { return }
                self.battery = level
            }
            ble = b
        }
    }

    private func adopt(_ t: RazerTransport) {
        if let old = transport, old !== t, old.kind != .bluetooth { old.close() }
        transport = t
        connection = .connected(t.kind)
        lastError = nil
        Task { await refreshAll() }
        rescheduleLiveRefresh()
    }

    // MARK: - Reading

    private func read(_ cmd: RazerCommand) async -> RazerResponse? {
        guard let t = transport, t.supports(cmd.cls) else { return nil }
        return try? await t.send(V4Pro.retarget(cmd, to: activeProfile))
    }

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }

        if let r = await read(V4Pro.firmware) { firmware = V4Pro.parseFirmware(r) }
        if let r = await read(V4Pro.serial) { serial = V4Pro.parseSerial(r) }

        // Synapse leaves the mouse in "driver mode" (it streams lighting itself). Without Synapse the
        // on-board effects only render in normal mode, so restore it if needed.
        if let r = await read(V4Pro.deviceMode), r[0] == 0x03 { _ = await read(V4Pro.setDeviceMode(0x00)) }

        // Which profile is live decides where every per-profile read below goes.
        if let r = await read(V4Pro.activeProfile), (1...UInt8(OnboardProfile.slotCount)).contains(r[0]) {
            activeProfile = r[0]
        }

        if let r = await read(V4Pro.dpiStages) {
            let parsed = V4Pro.parseStages(r)
            if !parsed.stages.isEmpty { stages = parsed.stages; activeStage = parsed.active }
        }
        if let r = await read(V4Pro.pollingRate), let p = V4Pro.parsePolling(r) { pollingRate = p }
        if let r = await read(V4Pro.smartTracking), let s = SmartTracking(rawValue: r[3]) { smartTracking = s }

        if let r = await read(V4Pro.scrollMode), let m = ScrollMode(rawValue: r[1]) { scrollMode = m }
        if let r = await read(V4Pro.enabledModes), r[1] != 0 {
            disabledModes = Set(ScrollMode.allCases.filter { r[1] & $0.maskBit == 0 })
        }
        if let r = await read(V4Pro.scrollAccel) { scrollAcceleration = r[1] != 0 }
        if let r = await read(V4Pro.scrollAccelLevel) { accelerationLevel = Int(min(r[1], 4)) }
        if let r = await read(V4Pro.smartReel) { smartReel = r[1] != 0 }
        if let r = await read(V4Pro.smartReelLevel) { smartReelLevel = Int(min(r[1], 4)) }

        if let r = await read(V4Pro.brightness(LightingZone.logo.rawValue)) { brightness = Double(r[2]) / 255 }
        for zone in LightingZone.allCases {
            if let r = await read(V4Pro.effect(zone)), let e = V4Pro.parseEffect(r) { effects[zone] = e }
        }
        if let r = await read(V4Pro.smartDimming) { smartDimming = r[1] != 0; smartDimPercent = V4Pro.dimPercent(code: r[2]) }

        if let r = await read(V4Pro.sleepTimeout) {
            let s = r.u16(0); if s > 0 { sleepMinutes = max(1, min(15, s / 60)) }
        }
        if let r = await read(V4Pro.lowPowerThreshold) { lowPowerPercent = Int(r[0]) * 100 / 255 }

        for b in MouseButton.allCases {
            if let r = await read(V4Pro.buttonAssignment(b)), let a = V4Pro.parseAssignment(r) { assignments[b] = a }
        }
        await refreshProfiles()
        await refreshLive()
    }

    /// Cheap values that change without the app: battery, charging, active DPI stage.
    func refreshLive() async {
        // The profile button on the mouse switches profiles without telling us; reload when it does.
        if !isLoading, !profileBusy, let r = await read(V4Pro.activeProfile),
           (1...UInt8(OnboardProfile.slotCount)).contains(r[0]), r[0] != activeProfile {
            activeProfile = r[0]
            await refreshAll()
            return
        }
        if let r = await read(V4Pro.battery) { battery = Int(r[1]) * 100 / 255 }
        if let r = await read(V4Pro.charging) { charging = r[1] != 0 }
        if let r = await read(V4Pro.dpiStages) {
            let parsed = V4Pro.parseStages(r)
            if !parsed.stages.isEmpty, parsed.stages.count == stages.count { activeStage = parsed.active }
        }
    }

    private func rescheduleLiveRefresh() {
        liveTimer?.invalidate()
        guard isConnected else { return }
        let interval: TimeInterval = windowVisible ? 4 : 60
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLive() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    // MARK: - Writing

    /// Sends a command; on failure runs `revert` and surfaces the error.
    private func write(_ cmds: [RazerCommand], revert: (() -> Void)? = nil) {
        guard let t = transport else { revert?(); return }
        let profile = activeProfile
        Task {
            do {
                for c in cmds { _ = try await t.send(V4Pro.retarget(c, to: profile)) }
            } catch {
                revert?()
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func selectStage(_ index: Int) {
        guard stages.indices.contains(index) else { return }
        let old = activeStage
        activeStage = index
        write([V4Pro.setStages(stages, active: index)]) { [weak self] in self?.activeStage = old }
    }

    func commitStages() {
        activeStage = min(activeStage, stages.count - 1)
        write([V4Pro.setStages(stages, active: activeStage)])
    }

    func addStage() {
        guard stages.count < 5 else { return }
        let next = min((stages.last?.x ?? 800) * 2, DPI.range.upperBound)
        stages.append(DPIStage(x: next, y: next))
        commitStages()
    }

    func removeStage(at index: Int) {
        guard stages.count > 1, stages.indices.contains(index) else { return }
        stages.remove(at: index)
        if activeStage >= index { activeStage = max(0, activeStage - 1) }
        commitStages()
    }

    func setPollingRate(_ p: PollingRate) {
        let old = pollingRate
        pollingRate = p
        write([V4Pro.setPollingRate(p)]) { [weak self] in self?.pollingRate = old }
    }

    func setSmartTracking(_ s: SmartTracking) {
        smartTracking = s
        write(V4Pro.setSmartTracking(s))
    }

    func setScrollMode(_ m: ScrollMode) {
        let old = scrollMode
        scrollMode = m
        write([V4Pro.setScrollMode(m)]) { [weak self] in self?.scrollMode = old }
    }

    func setModeDisabled(_ m: ScrollMode, _ disabled: Bool) {
        var next = disabledModes
        if disabled { next.insert(m) } else { next.remove(m) }
        guard next.count < ScrollMode.allCases.count else { return }   // at least one mode must stay enabled
        disabledModes = next
        let mask = ScrollMode.allCases.filter { !next.contains($0) }.reduce(UInt8(0)) { $0 | $1.maskBit }
        var cmds = [V4Pro.setEnabledModes(mask)]
        if next.contains(scrollMode), let first = ScrollMode.allCases.first(where: { !next.contains($0) }) {
            scrollMode = first
            cmds.append(V4Pro.setScrollMode(first))
        }
        write(cmds)
    }

    func setScrollAcceleration(_ on: Bool) { scrollAcceleration = on; write([V4Pro.setScrollAccel(on)]) }
    func setAccelerationLevel(_ l: Int) { accelerationLevel = l; write([V4Pro.setScrollAccelLevel(l)]) }
    func setSmartReel(_ on: Bool) { smartReel = on; write([V4Pro.setSmartReel(on)]) }
    func setSmartReelLevel(_ l: Int) { smartReelLevel = l; write([V4Pro.setSmartReelLevel(l)]) }

    func commitBrightness() { write([V4Pro.setBrightness(UInt8(brightness * 255))]) }

    func setEffect(_ e: LightingEffect, zones: [LightingZone]) {
        for z in zones { effects[z] = e }
        write(zones.map { V4Pro.setEffect(e, zone: $0) })
    }

    func setSmartDimming(on: Bool, percent: Int) {
        smartDimming = on; smartDimPercent = percent
        write([V4Pro.setSmartDimming(on: on, percent: percent)])
    }

    func commitSleep() { write([V4Pro.setSleepTimeout(seconds: sleepMinutes * 60)]) }
    func commitLowPower() { write([V4Pro.setLowPowerThreshold(percent: lowPowerPercent)]) }

    func assign(_ action: ButtonAction, to button: MouseButton) {
        guard button.isRemappable else { return }
        let old = assignments[button]
        assignments[button] = action
        write([V4Pro.setButton(button, action)]) { [weak self] in self?.assignments[button] = old }
    }

    func action(for b: MouseButton) -> ButtonAction { assignments[b] ?? b.factoryAction }

    // MARK: - Onboard memory

    /// Slots, names, colours and free storage. Class 05 also works over Bluetooth.
    func refreshProfiles() async {
        guard let list = await read(V4Pro.profileList) else { return }
        let ids = V4Pro.parseProfileList(list)
        var result: [OnboardProfile] = []
        for id in ids {
            var color = OnboardProfile.defaultColors[id] ?? .white
            if let r = await read(V4Pro.profileColor(id)), r[0] == id, r[1] | r[2] | r[3] != 0 {
                color = RGB(r: r[1], g: r[2], b: r[3])
            }
            var header: [UInt8]?
            if id != 1 { header = await readHeader(id) }
            result.append(OnboardProfile(id: id, name: header.map(ProfileHeader.name) ?? "", color: color, header: header))
        }
        profiles = result
        if let r = await read(V4Pro.storageInfo) { storage = V4Pro.parseStorage(r) }
    }

    private func readHeader(_ id: UInt8) async -> [UInt8]? {
        var bytes: [UInt8] = []
        for (offset, length) in V4Pro.headerChunks() {
            guard let r = await read(V4Pro.profileHeader(id, offset: offset, length: length)) else { break }
            bytes += r.args.dropFirst(5).prefix(length)
            bytes += [UInt8](repeating: 0, count: max(0, offset + length - bytes.count))
        }
        return bytes.count >= ProfileHeader.nameRange.upperBound
            ? bytes + [UInt8](repeating: 0, count: max(0, V4Pro.headerSize - bytes.count)) : nil
    }

    func profile(_ id: UInt8) -> OnboardProfile? { profiles.first { $0.id == id } }

    /// Runs a slot operation, reports failure, then re-reads the slots (and settings if the live profile changed).
    private func profileOperation(_ body: (RazerTransport) async throws -> Void) async {
        guard let t = transport, !profileBusy else { return }
        profileBusy = true
        let before = activeProfile
        do {
            try await body(t)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        if let r = await read(V4Pro.activeProfile), (1...UInt8(OnboardProfile.slotCount)).contains(r[0]) {
            activeProfile = r[0]
        }
        profileBusy = false
        if activeProfile != before { await refreshAll() } else { await refreshProfiles() }
    }

    func activateProfile(_ id: UInt8) async {
        guard id != activeProfile, profile(id) != nil else { return }
        await profileOperation { t in _ = try await t.send(V4Pro.setActiveProfile(id)) }
    }

    /// Copies the settings shown in the app (the live profile) into `slot`, creating it if needed.
    /// Same order Synapse uses when you drop a profile on a slot.
    func saveCurrentSettings(toSlot slot: UInt8, name: String) async {
        guard slot != activeProfile, (1...UInt8(OnboardProfile.slotCount)).contains(slot), supportsFullControl else { return }
        let exists = profile(slot) != nil
        let writesHeader = slot != 1   // the default profile has no header
        let header = ProfileHeader.withName(name, in: profile(slot)?.header ?? ProfileHeader.make(name: name))
        let dpi = stages.indices.contains(activeStage) ? stages[activeStage] : DPIStage(x: 800, y: 800)
        var settings: [RazerCommand] = [
            V4Pro.setPollingRate(pollingRate),
            V4Pro.setSmartReel(smartReel),
            V4Pro.setScrollMode(scrollMode),
            V4Pro.setActiveDPI(x: dpi.x, y: dpi.y),
            V4Pro.setStages(stages, active: activeStage),
            V4Pro.setBrightness(UInt8(brightness * 255))
        ]
        settings += MouseButton.allCases.filter(\.isRemappable).map { V4Pro.setButton($0, action(for: $0)) }

        await profileOperation { t in
            if !exists { _ = try await t.send(V4Pro.createProfile(slot)) }
            if writesHeader { try await Self.writeHeader(header, slot: slot, over: t) }
            for c in settings { _ = try await t.send(V4Pro.retarget(c, to: slot)) }
        }
    }

    func renameProfile(_ id: UInt8, to name: String) async {
        guard id != 1, let p = profile(id) else { return }
        let header = ProfileHeader.withName(name, in: p.header ?? ProfileHeader.make(name: name))
        await profileOperation { t in try await Self.writeHeader(header, slot: id, over: t) }
    }

    /// Frees the slot. The mouse falls back to the default profile if it was live.
    func deleteProfile(_ id: UInt8) async {
        guard id != 1, profile(id) != nil else { return }
        await profileOperation { t in _ = try await t.send(V4Pro.deleteProfile(id)) }
    }

    /// The final (58-byte) header chunk can come back as "failure" even though it's stored —
    /// Synapse ignores that too (PROTOCOL.md), so only earlier chunks are fatal.
    private static func writeHeader(_ header: [UInt8], slot: UInt8, over t: RazerTransport) async throws {
        let chunks = V4Pro.headerChunks()
        for (i, (offset, length)) in chunks.enumerated() {
            let cmd = V4Pro.setProfileHeader(slot, offset: offset, chunk: Array(header[offset..<offset + length]))
            do { _ = try await t.send(cmd) } catch TransportError.failed where i == chunks.count - 1 {}
        }
    }
}
