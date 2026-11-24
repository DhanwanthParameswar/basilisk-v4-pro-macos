import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview, performance, buttons, wheel, lighting, power, memory
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"; case .performance: "Performance"; case .buttons: "Buttons"
        case .wheel: "Scroll Wheel"; case .lighting: "Lighting"; case .power: "Power"
        case .memory: "Onboard Memory"
        }
    }

    var symbol: String {
        switch self {
        // Picked to share a ~15 pt footprint so the sidebar column reads evenly.
        case .overview: "computermouse"; case .performance: "gauge.with.dots.needle.50percent"
        case .buttons: "cursorarrow.click"; case .wheel: "arrow.up.and.down.circle"
        case .lighting: "lightspectrum.horizontal"; case .power: "bolt.circle"
        case .memory: "memorychip"
        }
    }

    /// Panes that need a USB/dongle link (Bluetooth can't change these).
    var needsFullControl: Bool { self != .overview && self != .memory }
}

struct RootView: View {
    @Environment(DeviceManager.self) private var device
    @SceneStorage("pane") private var pane: Pane = .overview
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { pane }, set: { if let p = $0 { pane = p } })) {
                DeviceCard()
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                Section {
                    ForEach(Pane.allCases) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Group {
                if device.isConnected {
                    detail(for: pane)
                } else {
                    DisconnectedView()
                }
            }
            // Minimum size belongs to the detail column, not the whole split view: NSSplitView then
            // derives the window minimum (sidebar + detail) itself and can animate the sidebar in
            // without fighting a fixed window constraint.
            .frame(minWidth: 560, minHeight: 520)
            .navigationTitle(pane.title)
            .toolbar {
                // Only add the item while loading: an always-present but empty item still gets a
                // Liquid Glass capsule, which flashes in the toolbar while the sidebar animates open.
                if device.isLoading {
                    ToolbarItem(placement: .primaryAction) {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .alert("Couldn't apply the change", isPresented: Binding(get: { device.lastError != nil },
                                                               set: { if !$0 { device.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(device.lastError ?? "")
        }
        .onAppear { device.windowVisible = true }
        .onDisappear { device.windowVisible = false }
        .onChange(of: scenePhase) { _, phase in device.windowVisible = phase == .active }
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .overview: OverviewPane()
        case .performance: PerformancePane()
        case .buttons: ButtonsPane()
        case .wheel: WheelPane()
        case .lighting: LightingPane()
        case .power: PowerPane()
        case .memory: MemoryPane()
        }
    }
}

/// Sidebar header: mini artwork, name, link, battery.
struct DeviceCard: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        HStack(spacing: 12) {
            MouseView(ledColors: device.effects.mapValues(\.previewColor), ledsOn: device.isConnected)
                .frame(width: 34, height: 54)
                .opacity(device.isConnected ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Basilisk V4 Pro").font(.headline)
                switch device.connection {
                case .connected(let k):
                    HStack(spacing: 8) {
                        Label(k.rawValue, systemImage: k.symbol)
                        BatteryBadge(level: device.battery, charging: device.charging)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                case .searching:
                    Text("Not connected").font(.caption).foregroundStyle(.secondary)
                case .unreachable:
                    Text("Mouse not answering").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct DisconnectedView: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        ContentUnavailableView {
            Label("Connect your Basilisk V4 Pro", systemImage: "computermouse")
        } description: {
            switch device.connection {
            case .unreachable(let why): Text(why)
            default: Text("Plug in the USB cable, use the HyperSpeed dongle, or pair it over Bluetooth. Basilisk finds it automatically.")
            }
        } actions: {
            ProgressView().controlSize(.small)
        }
    }
}
