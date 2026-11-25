import SwiftUI
import ServiceManagement
import ApplicationServices

/// Compact controls in the menu bar (window-style MenuBarExtra).
struct MenuBarContent: View {
    @Environment(DeviceManager.self) private var device
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MouseView(ledColors: device.effects.mapValues(\.previewColor), ledsOn: device.isConnected)
                    .frame(width: 26, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Basilisk V4 Pro").font(.headline)
                    if let k = device.kind {
                        Label(k.longName, systemImage: k.symbol).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Not connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if device.isConnected { BatteryBadge(level: device.battery, charging: device.charging).font(.callout) }
            }

            if device.isConnected, device.profiles.count > 1 {
                Picker("Profile", selection: Binding(get: { device.activeProfile },
                                                     set: { id in Task { await device.activateProfile(id) } })) {
                    ForEach(device.profiles) { Text($0.displayName).tag($0.id) }
                }
                .disabled(device.profileBusy || device.isLoading)
            }

            if device.supportsFullControl {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sensitivity").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Array(device.stages.enumerated()), id: \.element.id) { i, s in
                            Button { device.selectStage(i) } label: {
                                Text("\(s.x)").font(.caption.monospacedDigit()).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .tint(i == device.activeStage ? .accentColor : nil)
                        }
                    }
                }
                Picker("Polling", selection: Binding(get: { device.pollingRate }, set: { device.setPollingRate($0) })) {
                    ForEach(PollingRate.allCases) { Text("\($0.label) Hz").tag($0) }
                }
                Picker("Scroll", selection: Binding(get: { device.scrollMode }, set: { device.setScrollMode($0) })) {
                    ForEach(ScrollMode.allCases) { Text($0.label).tag($0) }
                }
            } else if device.isConnected {
                Text("Connect by cable or dongle for quick controls.").font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Open Basilisk") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct SettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $showMenuBar)
            Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {}
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }))
            Text("Your settings live on the mouse itself; Basilisk only needs to run while you change them. Keeping it in the menu bar shows battery and quick controls.")
                .font(.caption).foregroundStyle(.secondary)

            PermissionsSection()
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Lists the system permissions Basilisk uses, live status, and a way to grant them.
struct PermissionsSection: View {
    @State private var accessibility = AXIsProcessTrusted()
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("Permissions") {
            permissionRow(
                title: "Accessibility",
                detail: "Required for System Gestures — button actions macOS has no stored shortcut for, like Mission Control, Launchpad and switching Spaces.",
                granted: accessibility
            ) {
                GestureEngine.shared.requestAccessIfNeeded()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .onReceive(poll) { _ in
            let now = AXIsProcessTrusted()
            if now != accessibility { accessibility = now }
            if now { GestureEngine.shared.start() }   // tap installs as soon as access is granted
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, enable: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if granted {
                Label("Granted", systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(.green).font(.callout)
            } else {
                Button("Enable…", action: enable).buttonStyle(.borderedProminent)
            }
        }
    }
}
