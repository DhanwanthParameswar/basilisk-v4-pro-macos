import SwiftUI

/// The mouse artwork painted with the current lighting. Animates only when an effect actually moves
/// (spectrum / wave / breathing), at 20 fps, and TimelineView pauses it automatically when hidden.
struct LiveMouse: View {
    @Environment(DeviceManager.self) private var device
    var highlightedZone: LightingZone? = nil
    var onTapZone: ((LightingZone) -> Void)? = nil
    var highlightedButton: MouseButton? = nil
    var onTapButton: ((MouseButton) -> Void)? = nil

    private var animated: Bool {
        device.brightness > 0.02 && device.effects.values.contains { [.spectrum, .wave, .breathing].contains($0.kind) }
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                mouse(t: tl.date.timeIntervalSinceReferenceDate)
            }
        } else {
            mouse(t: 0)
        }
    }

    private func mouse(t: Double) -> some View {
        MouseView(ledColors: colors(t: t), highlightedZone: highlightedZone, highlightedButton: highlightedButton,
                  onTapZone: onTapZone, onTapButton: onTapButton)
    }

    private func colors(t: Double) -> [LightingZone: Color] {
        let level = max(device.brightness, 0.12)
        var out: [LightingZone: Color] = [:]
        for (i, zone) in LightingZone.allCases.enumerated() {
            let e = device.effects[zone] ?? LightingEffect()
            let c: Color
            switch e.kind {
            case .off: c = Color(hex: 0x252525)
            case .spectrum: c = Color(hue: (t * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1)
            case .wave:
                let dir = e.reverse ? -1.0 : 1.0
                c = Color(hue: (t * 0.12 * dir + Double(i) * 0.18).truncatingRemainder(dividingBy: 1) + (dir < 0 ? 1 : 0),
                          saturation: 0.9, brightness: 1)
            case .breathing:
                let phase = (sin(t * 2.2) + 1) / 2
                c = e.color.color.opacity(0.25 + 0.75 * phase)
            default: c = e.color.color
            }
            out[zone] = e.kind == .off ? c : c.opacity(0.35 + 0.65 * level)
        }
        return out
    }
}

struct OverviewPane: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                LiveMouse()
                    .frame(width: 230, height: 368)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Razer Basilisk V4 Pro").font(.largeTitle.weight(.semibold))
                        if let k = device.kind {
                            Label(k.longName, systemImage: k.symbol).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 6)

                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            StatTile(title: "Sensitivity",
                                     value: device.supportsFullControl ? "\(device.activeDPI)" : "—",
                                     detail: device.supportsFullControl ? "DPI · stage \(device.activeStage + 1) of \(device.stages.count)" : "Needs USB or dongle",
                                     symbol: "scope")
                            StatTile(title: "Polling Rate",
                                     value: device.supportsFullControl ? "\(device.pollingRate.rawValue)" : "—",
                                     detail: device.supportsFullControl ? "Hz" : "Needs USB or dongle",
                                     symbol: "waveform.path.ecg")
                        }
                        GridRow {
                            StatTile(title: "Battery",
                                     value: device.battery.map { "\($0)%" } ?? "—",
                                     detail: device.charging ? "Charging" : "On battery",
                                     symbol: BatteryBadge(level: device.battery, charging: device.charging).symbol,
                                     tint: (device.battery ?? 100) <= 15 ? .red : .green)
                            StatTile(title: "Scroll Wheel",
                                     value: device.supportsFullControl ? device.scrollMode.label : "—",
                                     detail: device.supportsFullControl ? (device.smartReel ? "Smart-Reel on" : "Smart-Reel off") : "Needs USB or dongle",
                                     symbol: device.scrollMode.symbol)
                        }
                    }

                    if device.supportsFullControl {
                        quickStages
                    } else {
                        LimitedConnectionNotice()
                            .padding(12)
                            .glassEffect(in: .rect(cornerRadius: 16))
                    }

                    HStack(spacing: 16) {
                        if let fw = device.firmware { LabeledContent("Firmware", value: fw) }
                        if let sn = device.serial, !sn.isEmpty { LabeledContent("Serial", value: sn) }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .animation(.snappy, value: device.activeStage)
    }

    private var quickStages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensitivity Stages").font(.headline)
            HStack(spacing: 8) {
                ForEach(Array(device.stages.enumerated()), id: \.element.id) { i, stage in
                    Button {
                        device.selectStage(i)
                    } label: {
                        Text("\(stage.x)")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(i == device.activeStage ? .accentColor : nil)
                    .controlSize(.large)
                }
            }
        }
    }
}
