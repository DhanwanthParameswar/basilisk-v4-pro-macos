import SwiftUI

struct PowerPane: View {
    @Environment(DeviceManager.self) private var device
    @State private var sleep: Double = 5
    @State private var lowPower: Double = 30

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    BatteryRing(level: device.battery, charging: device.charging)
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.battery.map { "\($0)%" } ?? "—")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(device.charging ? "Charging" : "On battery")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent("Sleep after") {
                    HStack {
                        Slider(value: $sleep, in: 1...15, step: 1) { editing in
                            if !editing { device.sleepMinutes = Int(sleep); device.commitSleep() }
                        }
                        .frame(maxWidth: 260)
                        Text("\(Int(sleep)) min").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
            } footer: {
                Text("The mouse sleeps after this long without movement and wakes when you move it.")
            }
            .disabled(!device.supportsFullControl)

            Section {
                LabeledContent("Low-power mode at") {
                    HStack {
                        Slider(value: $lowPower, in: 5...100, step: 5) { editing in
                            if !editing { device.lowPowerPercent = Int(lowPower); device.commitLowPower() }
                        }
                        .frame(maxWidth: 260)
                        Text("\(Int(lowPower))%").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Below this battery level the mouse turns its lighting off to last longer.")
            }
            .disabled(!device.supportsFullControl)

            if !device.supportsFullControl {
                Section { LimitedConnectionNotice() }
            }
        }
        .formStyle(.grouped)
        .onAppear { sleep = Double(device.sleepMinutes); lowPower = Double(device.lowPowerPercent) }
        .onChange(of: device.sleepMinutes) { _, v in sleep = Double(v) }
        .onChange(of: device.lowPowerPercent) { _, v in lowPower = Double(v) }
    }
}

/// Battery level ring drawn at its real size (no scaled widget gauge), with a glyph matching the level.
private struct BatteryRing: View {
    let level: Int?
    let charging: Bool

    private var fraction: Double { Double(level ?? 0) / 100 }
    private var tint: Color { (level ?? 100) <= 15 && !charging ? .red : .green }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: charging ? "bolt.fill" : BatteryBadge(level: level, charging: false).symbol)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(charging ? tint : .primary)
        }
        .padding(3)
        .animation(.smooth, value: fraction)
        .accessibilityElement()
        .accessibilityLabel(level.map { "Battery \($0) percent" } ?? "Battery unknown")
    }
}
