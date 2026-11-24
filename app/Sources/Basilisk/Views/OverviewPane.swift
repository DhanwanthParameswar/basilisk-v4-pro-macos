import SwiftUI

/// The mouse artwork painted with the current lighting. Animates only when something actually moves:
/// a spectrum / wave / breathing effect (20 fps) or the wheel rolling for a selected scroll input.
struct LiveMouse: View {
    @Environment(DeviceManager.self) private var device
    var highlightedZone: LightingZone? = nil
    var onTapZone: ((LightingZone) -> Void)? = nil
    var highlightedButton: MouseButton? = nil
    var onTapButton: ((MouseButton) -> Void)? = nil

    private var lightingAnimated: Bool {
        device.brightness > 0.02 && device.effects.values.contains { [.spectrum, .wave, .breathing].contains($0.kind) }
    }
    /// Wheel spin, eased in and out so selecting / deselecting a scroll input never jumps.
    @State private var roll = WheelRoll()
    @State private var settling = false
    /// The wheel rolls while a scroll input is selected (and briefly while it coasts to a stop);
    /// that needs full frame rate to look smooth.
    private var wheelRolling: Bool { highlightedButton?.wheelRoll != nil || settling }

    var body: some View {
        content
            .onChange(of: highlightedButton?.wheelRoll) { _, dir in
                let now = Date.timeIntervalSinceReferenceDate
                roll = roll.retarget(at: now, velocity: (dir ?? 0) * WheelRoll.speed)
                if dir == nil {
                    settling = true
                    Task { try? await Task.sleep(for: .seconds(WheelRoll.settleTime)); settling = false }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if lightingAnimated || wheelRolling {
            TimelineView(.animation(minimumInterval: wheelRolling ? nil : 1 / 20)) { tl in
                mouse(t: tl.date.timeIntervalSinceReferenceDate)
            }
        } else {
            mouse(t: Date.timeIntervalSinceReferenceDate)
        }
    }


    private func mouse(t: Double) -> some View {
        MouseView(ledColors: colors(t: t), highlightedZone: highlightedZone, highlightedButton: highlightedButton,
                  onTapZone: onTapZone, onTapButton: onTapButton, wheelTilt: highlightedButton?.wheelTilt ?? 0,
                  wheelRoll: roll.angle(at: t))
            .animation(.spring(duration: 0.35, bounce: 0.3), value: highlightedButton?.wheelTilt ?? 0)
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

/// Wheel rotation with an exponentially eased velocity: retargeting keeps angle and speed continuous,
/// so the wheel spins up, slows down and stops where it is instead of jumping.
struct WheelRoll {
    static let speed = 0.32          // rad/s ≈ 3 ribs a second at the wheel's top
    static let ease = 5.0            // 1/s: ~0.6 s to reach / lose speed
    static let settleTime = 1.2      // keep animating this long after a stop request

    var angle0 = 0.0, t0 = 0.0, v0 = 0.0, v1 = 0.0

    func angle(at t: Double) -> Double {
        let dt = max(0, t - t0)
        return angle0 + v1 * dt + (v0 - v1) * (1 - exp(-Self.ease * dt)) / Self.ease
    }
    func velocity(at t: Double) -> Double { v1 + (v0 - v1) * exp(-Self.ease * max(0, t - t0)) }
    func retarget(at t: Double, velocity target: Double) -> WheelRoll {
        WheelRoll(angle0: angle(at: t), t0: t, v0: velocity(at: t), v1: target)
    }
}
