import Foundation

/// Typed Basilisk V4 Pro protocol. Every builder/parser here maps to a row in DATASHEET.md;
/// the byte layouts were verified by capturing Synapse and replaying on hardware (PROTOCOL.md).
/// Byte 0 of most argument lists is the storage target: 0x01 = on-device profile store.
enum V4Pro {
    static let store: UInt8 = 0x01

    // MARK: Device
    static let firmware = RazerCommand(0x00, 0x81, size: 2)
    static let serial = RazerCommand(0x00, 0x82, size: 0x16)
    static let deviceMode = RazerCommand(0x00, 0x84, size: 2)
    static func setDeviceMode(_ mode: UInt8) -> RazerCommand { RazerCommand(0x00, 0x04, size: 2, [mode, 0]) }

    static func parseFirmware(_ r: RazerResponse) -> String { String(format: "%d.%02d", r[0], r[1]) }
    static func parseSerial(_ r: RazerResponse) -> String {
        String(bytes: r.args.prefix(22).filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
    }

    // MARK: Polling rate (HyperPolling)
    static let pollingRate = RazerCommand(0x00, 0xC0, size: 2, [store])
    static func setPollingRate(_ p: PollingRate) -> RazerCommand { RazerCommand(0x00, 0x40, size: 2, [store, p.divisor]) }
    static func parsePolling(_ r: RazerResponse) -> PollingRate? { PollingRate(divisor: r[1]) }

    // MARK: DPI
    static let activeDPI = RazerCommand(0x04, 0x85, size: 7, [store])
    static func setActiveDPI(x: Int, y: Int) -> RazerCommand {
        RazerCommand(0x04, 0x05, size: 7, [store, hi(x), lo(x), hi(y), lo(y), 0, 0])
    }
    static let dpiStages = RazerCommand(0x04, 0x86, size: 0x26, [store])

    /// GET reply: [store, activeStage (1-based), count, {id (1-based), xh, xl, yh, yl, 0, 0} × count]
    static func parseStages(_ r: RazerResponse) -> (stages: [DPIStage], active: Int) {
        let count = min(Int(r[2]), 5)
        var stages: [DPIStage] = []
        for i in 0..<count {
            let o = 3 + i * 7
            let x = r.u16(o + 1), y = r.u16(o + 3)
            if DPI.range.contains(x) { stages.append(DPIStage(x: x, y: DPI.range.contains(y) ? y : x)) }
        }
        let active = max(0, min(Int(r[1]) - 1, max(stages.count - 1, 0)))
        return (stages, active)
    }

    /// SET payload: [store, activeStage (1-based), count, {id (0-based), xh, xl, yh, yl, 0, 0} × count]
    static func setStages(_ stages: [DPIStage], active: Int) -> RazerCommand {
        var a: [UInt8] = [store, UInt8(active + 1), UInt8(stages.count)]
        for (i, s) in stages.enumerated() { a += [UInt8(i), hi(s.x), lo(s.x), hi(s.y), lo(s.y), 0, 0] }
        return RazerCommand(0x04, 0x06, size: UInt8(3 + 7 * stages.count), a)
    }

    // MARK: Sensor
    static func setSmartTracking(_ level: SmartTracking) -> [RazerCommand] {
        [RazerCommand(0x0B, 0x03, size: 3, [0x00, 0x04, 0x01]),
         RazerCommand(0x0B, 0x0B, size: 4, [0x00, 0x04, 0x01, level.rawValue])]
    }
    static let smartTracking = RazerCommand(0x0B, 0x8B, size: 4, [0x00, 0x04])

    // MARK: Scroll wheel
    static let scrollMode = RazerCommand(0x02, 0xB0, size: 2, [store])
    static func setScrollMode(_ m: ScrollMode) -> RazerCommand { RazerCommand(0x02, 0x30, size: 2, [store, m.rawValue]) }
    static let enabledModes = RazerCommand(0x15, 0x8B, size: 2, [store])
    static func setEnabledModes(_ mask: UInt8) -> RazerCommand { RazerCommand(0x15, 0x0B, size: 2, [store, mask]) }
    static let scrollAccel = RazerCommand(0x02, 0x96, size: 2, [store])
    static func setScrollAccel(_ on: Bool) -> RazerCommand { RazerCommand(0x02, 0x16, size: 2, [store, on ? 1 : 0]) }
    static let scrollAccelLevel = RazerCommand(0x02, 0xA2, size: 2, [store])
    static func setScrollAccelLevel(_ l: Int) -> RazerCommand { RazerCommand(0x02, 0x22, size: 2, [store, UInt8(l)]) }
    static let smartReel = RazerCommand(0x02, 0x97, size: 0x50, [store])
    static func setSmartReel(_ on: Bool) -> RazerCommand { RazerCommand(0x02, 0x17, size: 0x50, [store, on ? 1 : 0]) }
    static let smartReelLevel = RazerCommand(0x02, 0xA3, size: 2, [store])
    static func setSmartReelLevel(_ l: Int) -> RazerCommand { RazerCommand(0x02, 0x23, size: 2, [store, UInt8(l)]) }

    // MARK: Lighting (Chroma class 0x0F)
    static func brightness(_ zone: UInt8) -> RazerCommand { RazerCommand(0x0F, 0x84, size: 3, [store, zone]) }
    static func setBrightness(_ value: UInt8, zone: UInt8 = 0) -> RazerCommand {
        RazerCommand(0x0F, 0x04, size: 3, [store, zone, value])
    }
    static func effect(_ zone: LightingZone) -> RazerCommand { RazerCommand(0x0F, 0x82, size: 0x0C, [store, zone.rawValue]) }

    /// [store, zone, effectId, flags, rate, colorCount, r, g, b, …]
    static func setEffect(_ e: LightingEffect, zone: LightingZone) -> RazerCommand {
        var colors: [RGB] = []
        var flags: UInt8 = 0, rate: UInt8 = 0
        switch e.kind {
        case .off: break
        case .staticColor: colors = [e.color]
        case .breathing:
            colors = [e.color] + (e.secondColor.map { [$0] } ?? [])
            flags = UInt8(colors.count)
        case .spectrum: rate = 0
        case .wave: flags = e.reverse ? 2 : 1; rate = 40
        case .reactive: colors = [e.color]; rate = 2
        }
        var a: [UInt8] = [store, zone.rawValue, e.kind.rawValue, flags, rate, UInt8(colors.count)]
        for c in colors { a += [c.r, c.g, c.b] }
        return RazerCommand(0x0F, 0x02, size: UInt8(a.count), a)
    }

    static func parseEffect(_ r: RazerResponse) -> LightingEffect? {
        guard let kind = EffectKind(rawValue: r[2]) else { return nil }
        var e = LightingEffect(kind: kind)
        let n = Int(r[5])
        if n >= 1 { e.color = RGB(r: r[6], g: r[7], b: r[8]) }
        if n >= 2 { e.secondColor = RGB(r: r[9], g: r[10], b: r[11]) }
        if kind == .wave { e.reverse = r[3] == 2 }
        return e
    }

    // MARK: Power
    static let battery = RazerCommand(0x07, 0x80, size: 2)
    static let charging = RazerCommand(0x07, 0x84, size: 2)
    static let sleepTimeout = RazerCommand(0x07, 0x83, size: 2)
    static func setSleepTimeout(seconds: Int) -> RazerCommand { RazerCommand(0x07, 0x03, size: 2, [hi(seconds), lo(seconds)]) }
    static let lowPowerThreshold = RazerCommand(0x07, 0x81, size: 1)
    static func setLowPowerThreshold(percent: Int) -> RazerCommand {
        RazerCommand(0x07, 0x01, size: 1, [UInt8(max(0, min(255, percent * 255 / 100)))])
    }
    static let smartDimming = RazerCommand(0x07, 0x93, size: 3, [store])
    /// level code: 0 → 50 %, 1 → 25 %, 2 → 0 % dimming
    static func setSmartDimming(on: Bool, percent: Int) -> RazerCommand {
        let code: UInt8 = percent >= 50 ? 0 : (percent >= 25 ? 1 : 2)
        return RazerCommand(0x07, 0x13, size: 3, [store, on ? 1 : 0, code])
    }
    static func dimPercent(code: UInt8) -> Int { [50, 25, 0][Int(min(code, 2))] }

    // MARK: Buttons
    /// GET single assignment: [profile, buttonId, layer] → [profile, buttonId, layer, fnId, len, data…]
    static func buttonAssignment(_ b: MouseButton, hypershift: Bool = false) -> RazerCommand {
        RazerCommand(0x02, 0x8C, size: 0x0A, [store, b.rawValue, hypershift ? 1 : 0])
    }
    static func setButton(_ b: MouseButton, _ action: ButtonAction, hypershift: Bool = false) -> RazerCommand {
        let (fn, data) = action.encoded
        return RazerCommand(0x02, 0x0C, size: 0x0A, [store, b.rawValue, hypershift ? 1 : 0, fn, action.wireLength] + data)
    }
    static func parseAssignment(_ r: RazerResponse) -> ButtonAction? {
        guard r.args.count >= 5 else { return nil }
        let n = r[3] == 0x0E ? 3 : min(Int(r[4]), 5)   // 0x0E: [code, rate hi, rate lo] with length 1
        return ButtonAction(fnId: r[3], data: Array(r.args[5..<min(5 + n, r.args.count)]))
    }

    // MARK: Onboard memory (class 05 profiles, 06 storage) — PROTOCOL.md "Onboard memory"
    static let profileCount = RazerCommand(0x05, 0x80, size: 1)
    static let profileList = RazerCommand(0x05, 0x81, size: 0x50)
    static let activeProfile = RazerCommand(0x05, 0x84, size: 1)
    static func setActiveProfile(_ id: UInt8) -> RazerCommand { RazerCommand(0x05, 0x04, size: 1, [id]) }
    static func createProfile(_ id: UInt8) -> RazerCommand { RazerCommand(0x05, 0x02, size: 1, [id]) }
    static func deleteProfile(_ id: UInt8) -> RazerCommand { RazerCommand(0x05, 0x03, size: 1, [id]) }
    static func profileColor(_ id: UInt8) -> RazerCommand { RazerCommand(0x05, 0x8C, size: 4, [id]) }
    static let storageInfo = RazerCommand(0x06, 0x8E, size: 0x50)

    /// Header chunks: `[id, offset(2), total(2)=00fa, data…]`, ≤64 data bytes, size = chunk + 5.
    static let headerSize = 250
    static let headerChunk = 64
    static func profileHeader(_ id: UInt8, offset: Int, length: Int) -> RazerCommand {
        RazerCommand(0x05, 0x88, size: UInt8(length + 5), [id, hi(offset), lo(offset), hi(headerSize), lo(headerSize)])
    }
    static func setProfileHeader(_ id: UInt8, offset: Int, chunk: [UInt8]) -> RazerCommand {
        RazerCommand(0x05, 0x08, size: UInt8(chunk.count + 5),
                     [id, hi(offset), lo(offset), hi(headerSize), lo(headerSize)] + chunk)
    }
    static func headerChunks() -> [(offset: Int, length: Int)] {
        stride(from: 0, to: headerSize, by: headerChunk).map { ($0, min(headerChunk, headerSize - $0)) }
    }

    /// The firmware's reply lists the slots that hold a profile. Synapse reads it as
    /// `[count, id…]`; on hardware byte 0 looked like the slot maximum, so take any valid id after it.
    static func parseProfileList(_ r: RazerResponse) -> [UInt8] {
        var ids: [UInt8] = [1]
        for b in r.args.dropFirst().prefix(OnboardProfile.slotCount) where (1...UInt8(OnboardProfile.slotCount)).contains(b) && !ids.contains(b) {
            ids.append(b)
        }
        return ids.sorted()
    }

    /// `[maxId(2), maxMemory(4), available(4), recyclable(4)]`, big-endian.
    static func parseStorage(_ r: RazerResponse) -> OnboardStorage? {
        func u32(_ i: Int) -> Int { r.u16(i) << 16 | r.u16(i + 2) }
        let total = u32(2)
        guard total > 0 else { return nil }
        return OnboardStorage(total: total, available: u32(6), recyclable: u32(10))
    }

    /// Commands whose first argument selects the profile (DPI, polling, scroll wheel, brightness,
    /// buttons). Synapse's OBM writes exactly these per slot; everything else is device-wide.
    static func isPerProfile(_ c: RazerCommand) -> Bool {
        switch (c.cls, c.id & 0x7F) {
        case (0x00, 0x40), (0x04, 0x05), (0x04, 0x06), (0x02, 0x30), (0x02, 0x17), (0x02, 0x0C),
             (0x0F, 0x04): true
        default: false
        }
    }

    /// Points a per-profile command at `profile` instead of the default store.
    static func retarget(_ c: RazerCommand, to profile: UInt8) -> RazerCommand {
        guard profile != store, isPerProfile(c), !c.args.isEmpty, c.args[0] == store else { return c }
        var r = c
        r.args[0] = profile
        return r
    }

    // MARK: helpers
    static func hi(_ v: Int) -> UInt8 { UInt8((v >> 8) & 0xFF) }
    static func lo(_ v: Int) -> UInt8 { UInt8(v & 0xFF) }
}
