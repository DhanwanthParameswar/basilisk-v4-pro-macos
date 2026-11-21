import SwiftUI

/// Large figure tile used on the overview (Liquid Glass).
struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(tint.opacity(0.06)), in: .rect(cornerRadius: 16))
    }
}

/// Explains why a section is read-only on the current link.
struct LimitedConnectionNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited over Bluetooth").font(.callout.weight(.semibold))
                Text("The mouse only exposes device info and profiles over Bluetooth. Connect the USB cable or the HyperSpeed dongle to change these settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "dot.radiowaves.right").foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }
}

/// Battery glyph + percentage.
struct BatteryBadge: View {
    let level: Int?
    let charging: Bool

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        guard let l = level else { return "battery.0percent" }
        switch l {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        Label(level.map { "\($0)%" } ?? "—", systemImage: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle((level ?? 100) <= 15 && !charging ? .red : .primary)
            .monospacedDigit()
    }
}

/// Numeric DPI field that commits on Return / focus loss.
struct DPIField: View {
    @Binding var value: Int
    var onCommit: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("DPI", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 76)
            .focused($focused)
            .onAppear { text = "\(value)" }
            .onChange(of: value) { _, v in if !focused { text = "\(v)" } }
            .onSubmit(commit)
            .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        guard let v = Int(digits) else { text = "\(value)"; return }
        let clamped = min(max(v, DPI.range.lowerBound), DPI.range.upperBound)
        text = "\(clamped)"
        if clamped != value { value = clamped; onCommit() }
    }
}

/// Logarithmic slider mapping for 100…50 000 DPI so low values stay precise.
enum LogScale {
    static func toSlider(_ dpi: Int) -> Double {
        log(Double(dpi) / Double(DPI.range.lowerBound)) / log(Double(DPI.range.upperBound) / Double(DPI.range.lowerBound))
    }
    static func fromSlider(_ s: Double) -> Int {
        let v = Double(DPI.range.lowerBound) * pow(Double(DPI.range.upperBound) / Double(DPI.range.lowerBound), s)
        let step = v < 2000 ? 50.0 : (v < 10_000 ? 100.0 : 500.0)
        return Int((v / step).rounded() * step)
    }
}

extension LightingEffect {
    /// Static colour used to paint the artwork for this effect.
    var previewColor: Color {
        switch kind {
        case .off: Color(hex: 0x222222)
        case .spectrum, .wave: .accentColor
        default: color.color
        }
    }
}
