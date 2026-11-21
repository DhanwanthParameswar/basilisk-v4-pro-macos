import SwiftUI

struct WheelPane: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        Form {
            if !device.supportsFullControl {
                Section { LimitedConnectionNotice() }
            }

            Section {
                HStack(spacing: 12) {
                    ForEach(ScrollMode.allCases) { mode in
                        ModeCard(mode: mode)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Scroll Mode")
            } footer: {
                Text("The button behind the wheel cycles through the modes that are included.")
            }

            Section {
                Toggle("Scroll acceleration", isOn: Binding(get: { device.scrollAcceleration },
                                                             set: { device.setScrollAcceleration($0) }))
                LevelSlider(title: "Acceleration", value: device.accelerationLevel,
                            onCommit: { device.setAccelerationLevel($0) })
                    .disabled(!device.scrollAcceleration)
            } footer: {
                Text("Scrolling faster moves further, so long pages take fewer flicks.")
            }

            Section {
                Toggle("Smart-Reel", isOn: Binding(get: { device.smartReel }, set: { device.setSmartReel($0) }))
                LevelSlider(title: "Sensitivity", value: device.smartReelLevel,
                            onCommit: { device.setSmartReelLevel($0) })
                    .disabled(!device.smartReel)
            } footer: {
                Text("Automatically switches from tactile to free-spin when you flick the wheel hard.")
            }
        }
        .formStyle(.grouped)
        .disabled(!device.supportsFullControl)
    }
}

private struct ModeCard: View {
    @Environment(DeviceManager.self) private var device
    let mode: ScrollMode

    private var selected: Bool { device.scrollMode == mode }
    private var included: Bool { !device.disabledModes.contains(mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                device.setScrollMode(mode)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: mode.symbol)
                        .font(.title2)
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .symbolEffect(.bounce, value: selected)
                    Text(mode.label).font(.headline)
                    Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!included)

            Toggle("Include in cycle", isOn: Binding(get: { included },
                                                     set: { device.setModeDisabled(mode, !$0) }))
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(included && device.disabledModes.count >= ScrollMode.allCases.count - 1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(selected ? Color.accentColor.opacity(0.18) : .clear).interactive(),
                     in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .opacity(included ? 1 : 0.55)
        .animation(.snappy, value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 5-step (0–4) slider that only writes to the mouse when the user lets go.
struct LevelSlider: View {
    let title: String
    let value: Int
    let onCommit: (Int) -> Void
    @State private var local: Double = 0

    var body: some View {
        LabeledContent(title) {
            Slider(value: $local, in: 0...4, step: 1) {
                EmptyView()
            } minimumValueLabel: {
                Text("Low").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("High").font(.caption).foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                if !editing, Int(local) != value { onCommit(Int(local)) }
            }
            .frame(maxWidth: 280)
        }
        .onAppear { local = Double(value) }
        .onChange(of: value) { _, v in local = Double(v) }
    }
}
