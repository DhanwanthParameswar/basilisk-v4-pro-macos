import SwiftUI
import AppKit

@MainActor
enum Shared {
    static let device = DeviceManager()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Shared.device.start()
            GestureEngine.shared.requestAccessIfNeeded()
            GestureEngine.shared.start()
        }
    }
    /// Keep running in the menu bar after the window closes (when the extra is shown).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "showMenuBarExtra", default: true)
    }
}

private extension UserDefaults {
    func bool(forKey key: String, default d: Bool) -> Bool { object(forKey: key) == nil ? d : bool(forKey: key) }
}

@main
struct BasiliskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("showMenuBarExtra") private var showMenuBar = true

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), i + 1 < CommandLine.arguments.count {
            IconRenderer.render(to: CommandLine.arguments[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("Basilisk", id: "main") {
            RootView()
                .environment(Shared.device)
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent().environment(Shared.device)
        } label: {
            MenuBarLabel().environment(Shared.device)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

private struct MenuBarLabel: View {
    @Environment(DeviceManager.self) private var device
    var body: some View {
        if let b = device.battery, device.isConnected {
            Label("\(b)%", systemImage: "computermouse.fill").labelStyle(.titleAndIcon)
        } else {
            Image(systemName: device.isConnected ? "computermouse.fill" : "computermouse")
        }
    }
}

/// Renders the app icon (the artwork on a dark squircle) into an .iconset folder.
@MainActor
enum IconRenderer {
    struct IconView: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 230, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F33), Color(hex: 0x0C0D0E)],
                                         startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [RGB.razerGreen.color.opacity(0.35), .clear],
                               center: .center, startRadius: 10, endRadius: 420)
                MouseView(ledColors: [.wheel: RGB.razerGreen.color, .logo: RGB.razerGreen.color,
                                      .underglow: RGB.razerGreen.color])
                    .frame(width: 470, height: 752)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
                    .offset(x: 12)
            }
            .frame(width: 1024, height: 1024)
            .padding(0)
        }
    }

    static func render(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: IconView().frame(width: 1024, height: 1024)
            .scaleEffect(0.82)   // icon grid: ~10% margin on each side
            .frame(width: 1024, height: 1024))
        for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                             (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"),
                             (1024, "512x512@2x")] {
            renderer.scale = CGFloat(size) / 1024
            guard let cg = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("icon_\(name).png"))
        }
    }
}

