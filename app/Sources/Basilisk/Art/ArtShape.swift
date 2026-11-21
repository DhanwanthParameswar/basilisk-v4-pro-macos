import SwiftUI

/// One shape of the V4 Pro artwork (generated into MouseArtwork.swift by tools/svg2swift.py).
struct ArtShape: Sendable {
    enum Layer: Sendable {
        case body
        case wheelLED, logoLED, underglowLED
        case wheelSelect, logoSelect, underglowSelect
    }

    let layer: Layer
    let index: Int          // underglow LED number 1…5
    let fill: UInt32?
    let stroke: UInt32?
    let strokeWidth: CGFloat
    let opacity: Double
    let d: String

    var zone: LightingZone? {
        switch layer {
        case .wheelLED, .wheelSelect: .wheel
        case .logoLED, .logoSelect: .logo
        case .underglowLED, .underglowSelect: .underglow
        case .body: nil
        }
    }
    var isLED: Bool { layer == .wheelLED || layer == .logoLED || layer == .underglowLED }
    var isSelection: Bool { layer == .wheelSelect || layer == .logoSelect || layer == .underglowSelect }
}

/// Parsed, cached paths — built once, reused for every frame.
enum MouseArtPaths {
    struct Item { let shape: ArtShape; let path: Path }
    static let items: [Item] = MouseArtwork.shapes.map { Item(shape: $0, path: parse($0.d)) }

    /// Parses the normalised absolute "M x,y L x,y C … Z" strings emitted by the generator.
    static func parse(_ d: String) -> Path {
        var path = Path()
        var nums: [CGFloat] = []
        var cmd: Character = "M"
        var token = ""

        func flushNumber() {
            if !token.isEmpty, let v = Double(token) { nums.append(CGFloat(v)) }
            token = ""
        }
        func emit() {
            switch cmd {
            case "M" where nums.count >= 2: path.move(to: CGPoint(x: nums[0], y: nums[1]))
            case "L" where nums.count >= 2: path.addLine(to: CGPoint(x: nums[0], y: nums[1]))
            case "C" where nums.count >= 6:
                path.addCurve(to: CGPoint(x: nums[4], y: nums[5]),
                              control1: CGPoint(x: nums[0], y: nums[1]),
                              control2: CGPoint(x: nums[2], y: nums[3]))
            case "Z": path.closeSubpath()
            default: break
            }
            nums.removeAll(keepingCapacity: true)
        }

        for ch in d {
            if ch == "M" || ch == "L" || ch == "C" || ch == "Z" {
                flushNumber(); emit(); cmd = ch
                if ch == "Z" { emit() }
            } else if ch == "," {
                flushNumber()
            } else if ch == "-" && !token.isEmpty {
                flushNumber(); token = "-"
            } else {
                token.append(ch)
            }
        }
        flushNumber(); emit()
        return path
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
