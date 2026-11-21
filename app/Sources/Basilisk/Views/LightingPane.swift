import SwiftUI

struct LightingPane: View {
    @Environment(DeviceManager.self) private var device
    /// nil = edit all zones together.
    @State private var zone: LightingZone? = nil
    @State private var brightness: Double = 0

    private var zones: [LightingZone] { zone.map { [$0] } ?? LightingZone.allCases }
    private var current: LightingEffect { device.effects[zones[0]] ?? LightingEffect() }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 12) {
                LiveMouse(highlightedZone: zone, onTapZone: { z in zone = (zone == z ? nil : z) })
                    .frame(width: 190, height: 304)
                Picker("Zone", selection: $zone) {
                    Text("All Zones").tag(LightingZone?.none)
                    ForEach(LightingZone.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .labelsHidden()
                .frame(width: 170)
                Text("Click a zone on the mouse to edit it on its own.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 170)
            }
            .padding(24)

            Form {
                if !device.supportsFullControl {
                    Section { LimitedConnectionNotice() }
                }

                Section("Brightness") {
                    HStack {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: $brightness, in: 0...1) { editing in
                            if !editing { device.brightness = brightness; device.commitBrightness() }
                        }
                        Image(systemName: "sun.max").foregroundStyle(.secondary)
                        Text("\(Int(brightness * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }

                Section(zone.map { "Effect · \($0.label)" } ?? "Effect · All Zones") {
                    EffectGrid(selected: current.kind) { kind in
                        var e = current; e.kind = kind
                        device.setEffect(e, zones: zones)
                    }
                    if current.kind.usesColor {
                        ColorPicker("Colour", selection: Binding(
                            get: { current.color.color },
                            set: { c in var e = current; e.color = RGB(c); device.setEffect(e, zones: zones) }),
                                    supportsOpacity: false)
                        ColorSwatches { rgb in var e = current; e.color = rgb; device.setEffect(e, zones: zones) }
                    }
                    if current.kind == .wave {
                        Picker("Direction", selection: Binding(
                            get: { current.reverse },
                            set: { r in var e = current; e.reverse = r; device.setEffect(e, zones: zones) })) {
                            Text("Front to back").tag(false)
                            Text("Back to front").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Toggle("Dim lighting when idle", isOn: Binding(
                        get: { device.smartDimming },
                        set: { device.setSmartDimming(on: $0, percent: device.smartDimPercent) }))
                    Picker("Dim to", selection: Binding(
                        get: { device.smartDimPercent },
                        set: { device.setSmartDimming(on: device.smartDimming, percent: $0) })) {
                        Text("Off").tag(0); Text("25%").tag(25); Text("50%").tag(50)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!device.smartDimming)
                } header: {
                    Text("Battery Saving")
                } footer: {
                    Text("Lighting dims while the mouse is still, saving battery.")
                }
            }
            .formStyle(.grouped)
        }
        .disabled(!device.supportsFullControl)
        .onAppear { brightness = device.brightness }
        .onChange(of: device.brightness) { _, b in brightness = b }
    }
}

private struct EffectGrid: View {
    let selected: EffectKind
    let onSelect: (EffectKind) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(EffectKind.allCases) { kind in
                Button {
                    onSelect(kind)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.title3)
                            .symbolRenderingMode(kind == .spectrum ? .multicolor : .hierarchical)
                        Text(kind.label).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glass)
                .tint(kind == selected ? .accentColor : nil)
                .accessibilityAddTraits(kind == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ColorSwatches: View {
    let onPick: (RGB) -> Void
    private let swatches: [RGB] = [
        .razerGreen, RGB(r: 255, g: 255, b: 255), RGB(r: 255, g: 40, b: 40), RGB(r: 255, g: 140, b: 0),
        RGB(r: 255, g: 220, b: 0), RGB(r: 0, g: 200, b: 255), RGB(r: 40, g: 90, b: 255), RGB(r: 170, g: 60, b: 255),
        RGB(r: 255, g: 60, b: 180)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { _, rgb in
                Button { onPick(rgb) } label: {
                    Circle().fill(rgb.color)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
