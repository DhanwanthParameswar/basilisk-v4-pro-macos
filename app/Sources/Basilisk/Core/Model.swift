import Foundation
import SwiftUI

// MARK: - Performance

struct DPIStage: Identifiable, Equatable, Sendable {
    var id = UUID()
    var x: Int
    var y: Int
    var value: Int { x }
}

enum DPI {
    static let range = 100...50_000
    static let presets = [400, 800, 1600, 3200, 6400]
}

enum PollingRate: Int, CaseIterable, Identifiable, Sendable {
    case hz125 = 125, hz500 = 500, hz1000 = 1000, hz2000 = 2000, hz4000 = 4000, hz8000 = 8000
    var id: Int { rawValue }
    var divisor: UInt8 { UInt8(8000 / rawValue) }
    var label: String { rawValue >= 1000 ? "\(rawValue / 1000)K" : "\(rawValue)" }
    init?(divisor: UInt8) {
        guard divisor > 0 else { return nil }
        self.init(rawValue: 8000 / Int(divisor))
    }
}

enum SmartTracking: UInt8, CaseIterable, Identifiable, Sendable {
    case low = 0, medium = 1, high = 2
    var id: UInt8 { rawValue }
    var label: String { ["Low", "Medium", "High"][Int(rawValue)] }
}

// MARK: - Scroll wheel

enum ScrollMode: UInt8, CaseIterable, Identifiable, Sendable {
    case tactile = 0, freeSpin = 1, precision = 2
    var id: UInt8 { rawValue }
    var label: String { ["Tactile", "Free-Spin", "Precision Tactile"][Int(rawValue)] }
    var detail: String {
        ["24-step notched scrolling", "Frictionless, fast scrolling", "Fine, light notches"][Int(rawValue)]
    }
    var symbol: String { ["dial.medium", "arrow.trianglehead.2.clockwise.rotate.90", "dial.low"][Int(rawValue)] }
    /// Bit used in the enabled-modes mask (`15:0b`).
    var maskBit: UInt8 { [1, 2, 4][Int(rawValue)] }
}

// MARK: - Lighting

struct RGB: Equatable, Sendable, Codable {
    var r: UInt8, g: UInt8, b: UInt8
    static let razerGreen = RGB(r: 0x44, g: 0xD6, b: 0x2C)
    static let white = RGB(r: 255, g: 255, b: 255)

    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        r = UInt8(max(0, min(255, ns.redComponent * 255)))
        g = UInt8(max(0, min(255, ns.greenComponent * 255)))
        b = UInt8(max(0, min(255, ns.blueComponent * 255)))
    }
}

enum LightingZone: UInt8, CaseIterable, Identifiable, Sendable {
    case wheel = 0x01, logo = 0x04, underglow = 0x0A
    var id: UInt8 { rawValue }
    var label: String {
        switch self { case .wheel: "Scroll Wheel"; case .logo: "Logo"; case .underglow: "Underglow" }
    }
}

enum EffectKind: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0, staticColor = 1, breathing = 2, spectrum = 3, wave = 4, reactive = 5
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .off: "Off"; case .staticColor: "Static"; case .breathing: "Breathing"
        case .spectrum: "Spectrum Cycling"; case .wave: "Wave"; case .reactive: "Reactive"
        }
    }
    var symbol: String {
        switch self {
        case .off: "lightbulb.slash"; case .staticColor: "circle.fill"; case .breathing: "wind"
        case .spectrum: "rainbow"; case .wave: "water.waves"; case .reactive: "hand.tap"
        }
    }
    var usesColor: Bool { self == .staticColor || self == .breathing || self == .reactive }
}

struct LightingEffect: Equatable, Sendable {
    var kind: EffectKind = .spectrum
    var color: RGB = .razerGreen
    var secondColor: RGB? = nil
    var reverse = false
}

// MARK: - Buttons

enum MouseButton: UInt8, CaseIterable, Identifiable, Sendable {
    case left = 1, right = 2, wheelClick = 3, back = 4, forward = 5
    case wheelUp = 9, wheelDown = 10, tiltLeft = 52, tiltRight = 53
    case profile = 14, sensitivity = 96, scrollMode = 106, hypershift = 57, aiPrompt = 128

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .left: "Left Click"; case .right: "Right Click"; case .wheelClick: "Wheel Click"
        case .back: "Mouse Button 4"; case .forward: "Mouse Button 5"
        case .wheelUp: "Scroll Up"; case .wheelDown: "Scroll Down"
        case .tiltLeft: "Tilt Left"; case .tiltRight: "Tilt Right"
        case .profile: "Profile Button"; case .sensitivity: "Sensitivity Stage Button"
        case .scrollMode: "Scroll Mode Toggle"; case .hypershift: "Razer Hypershift"; case .aiPrompt: "AI Prompt Button"
        }
    }

    var group: String {
        switch self {
        case .left, .right, .wheelClick: "Primary"
        case .back, .forward, .hypershift, .aiPrompt: "Side"
        case .wheelUp, .wheelDown, .tiltLeft, .tiltRight: "Scroll Wheel"
        case .profile, .sensitivity, .scrollMode: "Top"
        }
    }

    /// Left click can't be remapped (so you can never lock yourself out).
    var isRemappable: Bool { self != .left }

    var factoryAction: ButtonAction {
        switch self {
        case .left: .mouse(1); case .right: .mouse(2); case .wheelClick: .mouse(3)
        case .back: .mouse(4); case .forward: .mouse(5)
        case .wheelUp: .mouse(9); case .wheelDown: .mouse(10)
        case .tiltLeft: .mouseRepeat(code: 0x68, rate: 20); case .tiltRight: .mouseRepeat(code: 0x69, rate: 20)
        case .sensitivity: .dpiCycleUp; case .profile: .profileCycle
        case .scrollMode: .scrollModeCycle; case .hypershift: .hypershift
        case .aiPrompt: .disabled
        }
    }
}

/// What a button does. Encodes to the firmware's (fnId, data) pair for `02:0c`.
enum ButtonAction: Hashable, Sendable {
    case mouse(UInt8)
    /// Mouse code that auto-repeats while held (tilt → horizontal scroll). fnId 0x0E.
    case mouseRepeat(code: UInt8, rate: UInt16)
    case key(modifiers: UInt8, usage: UInt8)
    case dpiUp, dpiDown, dpiCycleUp, dpiCycleDown
    case dpiClutch(Int)
    case profileCycle
    case scrollModeCycle
    case hypershift
    case disabled
    case other(fnId: UInt8, data: [UInt8])

    var encoded: (fnId: UInt8, data: [UInt8]) {
        switch self {
        case .mouse(let c): (0x01, [c])
        case .mouseRepeat(let c, let r): (0x0E, [c, UInt8(r >> 8), UInt8(r & 0xFF)])
        case .key(let m, let u): (0x02, [m, u])
        case .dpiUp: (0x06, [1])
        case .dpiDown: (0x06, [2])
        case .dpiClutch(let d): (0x06, [5, UInt8(d >> 8), UInt8(d & 0xFF), UInt8(d >> 8), UInt8(d & 0xFF)])
        case .dpiCycleUp: (0x06, [6])
        case .dpiCycleDown: (0x06, [7])
        case .profileCycle: (0x07, [4])
        case .scrollModeCycle: (0x12, [1])
        case .hypershift: (0x0C, [1])
        case .disabled: (0x00, [])
        case .other(let f, let d): (f, d)
        }
    }

    init(fnId: UInt8, data: [UInt8]) {
        let d0 = data.first ?? 0
        switch (fnId, d0) {
        case (0x00, _): self = .disabled
        case (0x01, _): self = .mouse(d0)
        case (0x0E, _) where data.count >= 3: self = .mouseRepeat(code: d0, rate: UInt16(data[1]) << 8 | UInt16(data[2]))
        case (0x02, _) where data.count >= 2: self = .key(modifiers: data[0], usage: data[1])
        case (0x06, 1): self = .dpiUp
        case (0x06, 2): self = .dpiDown
        case (0x06, 5) where data.count >= 3: self = .dpiClutch(Int(data[1]) << 8 | Int(data[2]))
        case (0x06, 6): self = .dpiCycleUp
        case (0x06, 7): self = .dpiCycleDown
        case (0x07, 4): self = .profileCycle
        case (0x12, 1): self = .scrollModeCycle
        case (0x0C, _): self = .hypershift
        default: self = .other(fnId: fnId, data: data)
        }
    }

    /// Length byte the firmware stores for this action (0x0E counts only the code, not the rate).
    var wireLength: UInt8 {
        if case .mouseRepeat = self { return 1 }
        return UInt8(encoded.data.count)
    }

    var label: String {
        switch self {
        case .mouse(let c):
            switch c {
            case 1: "Left Click"; case 2: "Right Click"; case 3: "Middle Click"
            case 4: "Back"; case 5: "Forward"; case 9: "Scroll Up"; case 10: "Scroll Down"
            default: "Mouse Button \(c)"
            }
        case .mouseRepeat(let c, _):
            switch c { case 0x68: "Scroll Left"; case 0x69: "Scroll Right"; default: "Mouse Button \(c) (repeat)" }
        case .key(let m, let u): KeyNames.describe(modifiers: m, usage: u)
        case .dpiUp: "Sensitivity Up"; case .dpiDown: "Sensitivity Down"
        case .dpiCycleUp: "Cycle Sensitivity Up"; case .dpiCycleDown: "Cycle Sensitivity Down"
        case .dpiClutch(let d): "Sensitivity Clutch (\(d) DPI)"
        case .profileCycle: "Cycle Profile"; case .scrollModeCycle: "Cycle Scroll Mode"
        case .hypershift: "Hypershift"; case .disabled: "Disabled"
        case .other(let f, _): String(format: "Custom (0x%02X)", f)
        }
    }
}

// MARK: - Keyboard key naming (HID usage page 7)

enum KeyNames {
    /// HID usages for F1–F12 (0x3A–0x45) then F13–F24 (0x68–0x73).
    static let functionKeys: [UInt8] = Array(0x3A...0x45) + Array(0x68...0x73)

    static func describe(modifiers: UInt8, usage: UInt8) -> String {
        var s = ""
        if modifiers & 0x11 != 0 { s += "⌃" }
        if modifiers & 0x44 != 0 { s += "⌥" }
        if modifiers & 0x22 != 0 { s += "⇧" }
        if modifiers & 0x88 != 0 { s += "⌘" }
        return s + name(usage)
    }

    static func name(_ u: UInt8) -> String {
        switch u {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(65) + u - 0x04))
        case 0x1E...0x26: return String(u - 0x1D)
        case 0x27: return "0"
        case 0x28: return "Return"; case 0x29: return "Esc"; case 0x2A: return "Delete"
        case 0x2B: return "Tab"; case 0x2C: return "Space"
        case 0x3A...0x45: return "F\(u - 0x39)"
        case 0x68...0x73: return "F\(u - 0x68 + 13)"
        case 0x4F: return "→"; case 0x50: return "←"; case 0x51: return "↓"; case 0x52: return "↑"
        case 0x0: return "None"
        default: return String(format: "Key 0x%02X", u)
        }
    }

    /// macOS virtual key code → HID usage, for the key recorder.
    static func usage(forKeyCode code: UInt16) -> UInt8? {
        let map: [UInt16: UInt8] = [
            0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0A, 4: 0x0B, 34: 0x0C, 38: 0x0D,
            40: 0x0E, 37: 0x0F, 46: 0x10, 45: 0x11, 31: 0x12, 35: 0x13, 12: 0x14, 15: 0x15, 1: 0x16, 17: 0x17,
            32: 0x18, 9: 0x19, 13: 0x1A, 7: 0x1B, 16: 0x1C, 6: 0x1D,
            18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 23: 0x22, 22: 0x23, 26: 0x24, 28: 0x25, 25: 0x26, 29: 0x27,
            36: 0x28, 53: 0x29, 51: 0x2A, 48: 0x2B, 49: 0x2C,
            122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F, 98: 0x40, 100: 0x41, 101: 0x42,
            109: 0x43, 103: 0x44, 111: 0x45,
            105: 0x68, 107: 0x69, 113: 0x6A, 106: 0x6B, 64: 0x6C, 79: 0x6D, 80: 0x6E, 90: 0x6F,   // F13–F20 (extended keyboards)
            124: 0x4F, 123: 0x50, 125: 0x51, 126: 0x52
        ]
        return map[code]
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> UInt8 {
        var m: UInt8 = 0
        if flags.contains(.control) { m |= 0x01 }
        if flags.contains(.shift) { m |= 0x02 }
        if flags.contains(.option) { m |= 0x04 }
        if flags.contains(.command) { m |= 0x08 }
        return m
    }
}

// MARK: - Onboard memory

/// One of the mouse's profile slots. Slot 1 is the default profile and always exists;
/// slots 2–5 are the onboard slots Synapse calls "On-Board Memory".
struct OnboardProfile: Identifiable, Equatable, Sendable {
    static let slotCount = 5
    /// Indicator colours the firmware shows when you switch profiles (used if 05:8c gives nothing).
    static let defaultColors: [UInt8: RGB] = [
        1: .white, 2: RGB(r: 255, g: 0, b: 0), 3: RGB(r: 0, g: 255, b: 0),
        4: RGB(r: 0, g: 0, b: 255), 5: RGB(r: 0, g: 255, b: 255)
    ]

    let id: UInt8
    var name: String
    var color: RGB
    /// Raw 250-byte header (GUID · name · owner · mapping hash), kept so a rename preserves the rest.
    var header: [UInt8]?

    var isDefault: Bool { id == 1 }
    var displayName: String {
        if !name.isEmpty { return name }
        return isDefault ? "Default" : "Profile \(id)"
    }
    var colorName: String {
        ["White", "Red", "Green", "Blue", "Cyan"][Int(max(1, min(id, 5))) - 1]
    }
}

/// Macro/profile flash storage (`06:8e`). Each extra profile costs 256 bytes.
struct OnboardStorage: Equatable, Sendable {
    var total: Int
    var available: Int
    var recyclable: Int
    var used: Int { max(0, total - available) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// 250-byte profile header: GUID 16 · UTF-8 name 100 · owner 128 · key-mapping hash 6.
enum ProfileHeader {
    static let nameRange = 16..<116

    static func name(from header: [UInt8]) -> String {
        guard header.count >= nameRange.upperBound else { return "" }
        let bytes = header[nameRange].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// New header with a fresh GUID and no owner (owner/hash are Synapse/Razer ID bookkeeping).
    static func make(name: String) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: V4Pro.headerSize)
        h.replaceSubrange(0..<16, with: guidBytes(UUID()))
        return withName(name, in: h)
    }

    static func withName(_ name: String, in header: [UInt8]) -> [UInt8] {
        var h = header.count == V4Pro.headerSize ? header : make(name: "")
        var bytes = Array(name.utf8)
        // Truncate on a character boundary so the firmware never stores half a UTF-8 sequence.
        if bytes.count > nameRange.count {
            var s = ""
            for ch in name where s.utf8.count + String(ch).utf8.count <= nameRange.count { s.append(ch) }
            bytes = Array(s.utf8)
        }
        h.replaceSubrange(nameRange, with: bytes + [UInt8](repeating: 0, count: nameRange.count - bytes.count))
        return h
    }

    /// Synapse stores the GUID in Windows (mixed-endian) order: first three fields little-endian.
    static func guidBytes(_ uuid: UUID) -> [UInt8] {
        let u = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        return [u[3], u[2], u[1], u[0], u[5], u[4], u[7], u[6]] + u[8..<16]
    }
}
