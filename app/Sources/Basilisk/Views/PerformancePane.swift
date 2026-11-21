import SwiftUI

struct PerformancePane: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        @Bindable var device = device
        Form {
            if !device.supportsFullControl {
                Section { LimitedConnectionNotice() }
            }

            Section {
                ForEach(Array(device.stages.indices), id: \.self) { i in
                    StageRow(index: i)
                }
                Button {
                    device.addStage()
                } label: {
                    Label("Add Stage", systemImage: "plus")
                }
                .disabled(device.stages.count >= 5)
            } header: {
                Text("Sensitivity Stages")
            } footer: {
                Text("The sensitivity button cycles through these stages. Click a stage’s circle to make it active. 100–50,000 DPI.")
            }

            Section {
                Picker("Polling rate", selection: Binding(get: { device.pollingRate }, set: { device.setPollingRate($0) })) {
                    ForEach(PollingRate.allCases) { Text("\($0.label) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Polling Rate")
            } footer: {
                Text("How often the mouse reports to your Mac. Higher is smoother but uses more battery; 4000 Hz and 8000 Hz work best over the HyperSpeed dongle or cable.")
            }

            Section {
                Picker("Lift-off distance", selection: Binding(get: { device.smartTracking }, set: { device.setSmartTracking($0) })) {
                    ForEach(SmartTracking.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Sensor")
            } footer: {
                Text("Smart Tracking: how high you can lift the mouse before it stops tracking.")
            }
        }
        .formStyle(.grouped)
        .disabled(!device.supportsFullControl)
        .animation(.snappy, value: device.stages.count)
    }
}

private struct StageRow: View {
    @Environment(DeviceManager.self) private var device
    let index: Int
    @State private var slider: Double = 0

    var body: some View {
        @Bindable var device = device
        if device.stages.indices.contains(index) {
            HStack(spacing: 12) {
                Button {
                    device.selectStage(index)
                } label: {
                    Image(systemName: index == device.activeStage ? "largecircle.fill.circle" : "circle")
                        .font(.title3)
                        .foregroundStyle(index == device.activeStage ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Make this the active stage")

                Text("Stage \(index + 1)")
                    .frame(width: 58, alignment: .leading)

                Slider(value: $slider, in: 0...1) { editing in
                    if !editing { device.commitStages() }
                }
                .onChange(of: slider) { _, s in
                    let v = LogScale.fromSlider(s)
                    if device.stages.indices.contains(index), device.stages[index].x != v {
                        device.stages[index].x = v
                        device.stages[index].y = v
                    }
                }

                DPIField(value: Binding(
                    get: { device.stages.indices.contains(index) ? device.stages[index].x : 0 },
                    set: { v in
                        guard device.stages.indices.contains(index) else { return }
                        device.stages[index].x = v; device.stages[index].y = v
                        slider = LogScale.toSlider(v)
                    }), onCommit: { device.commitStages() })

                Button {
                    device.removeStage(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(device.stages.count <= 1)
                .help("Remove stage")
            }
            .onAppear { slider = LogScale.toSlider(device.stages[index].x) }
            .onChange(of: device.stages.count) { _, _ in
                if device.stages.indices.contains(index) { slider = LogScale.toSlider(device.stages[index].x) }
            }
        }
    }
}
