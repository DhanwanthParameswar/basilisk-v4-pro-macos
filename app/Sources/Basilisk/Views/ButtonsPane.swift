import SwiftUI
import AppKit

struct ButtonsPane: View {
    @Environment(DeviceManager.self) private var device
    @State private var selected: MouseButton? = .back
    @State private var recording: MouseButton?
    @State private var clutchFor: MouseButton?
    /// Rows sliding under the pointer while we scroll to a clicked part must not steal the selection.
    @State private var ignoreRowHoverUntil = Date.distantPast

    private var groups: [(String, [MouseButton])] {
        let order = ["Primary", "Side", "Scroll Wheel", "Top"]
        return order.map { g in (g, MouseButton.allCases.filter { $0.group == g }) }
    }

    var body: some View {
        ScrollViewReader { proxy in
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 12) {
                LiveMouse(highlightedButton: selected, onTapButton: { b in
                    selected = b
                    ignoreRowHoverUntil = .now.addingTimeInterval(0.8)
                    withAnimation(.snappy) { proxy.scrollTo(b, anchor: .center) }
                })
                    .frame(width: 210, height: 336)
                Text("Click a part of the mouse to find its button.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 180)
            }
            .padding(24)

            Form {
                if !device.supportsFullControl {
                    Section { LimitedConnectionNotice() }
                }
                ForEach(groups, id: \.0) { group, buttons in
                    Section(group) {
                        ForEach(buttons) { b in
                            ButtonRow(button: b, isSelected: selected == b,
                                      onRecord: { recording = b }, onClutch: { clutchFor = b })
                                .id(b)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = b }
                                .onHover { if $0, Date.now > ignoreRowHoverUntil { selected = b } }
                        }
                    }
                }
                Section {
                    Button("Restore Factory Assignments", role: .destructive) {
                        for b in MouseButton.allCases where b.isRemappable && device.action(for: b) != b.factoryAction {
                            device.assign(b.factoryAction, to: b)
                        }
                    }
                } footer: {
                    Text("Assignments are saved on the mouse, so they work on any computer without this app. Left click can’t be remapped.")
                }
            }
            .formStyle(.grouped)
        }
        }
        .disabled(!device.supportsFullControl)
        .sheet(item: $recording) { b in
            KeyRecorderSheet(button: b) { action in
                if let action { device.assign(action, to: b) }
                recording = nil
            }
        }
        .sheet(item: $clutchFor) { b in
            ClutchSheet(initial: { if case .dpiClutch(let d) = device.action(for: b) { return d } else { return 400 } }()) { dpi in
                if let dpi { device.assign(.dpiClutch(dpi), to: b) }
                clutchFor = nil
            }
        }
    }
}

private struct ButtonRow: View {
    @Environment(DeviceManager.self) private var device
    let button: MouseButton
    let isSelected: Bool
    let onRecord: () -> Void
    let onClutch: () -> Void

    var body: some View {
        let action = device.action(for: button)
        LabeledContent {
            if button.isRemappable {
                Menu(action.label) {
                    Button("Default (\(button.factoryAction.label))") { device.assign(button.factoryAction, to: button) }
                    Divider()
                    Section("Mouse") {
                        ForEach([ButtonAction.mouse(1), .mouse(2), .mouse(3), .mouse(4), .mouse(5),
                                 .mouse(9), .mouse(10), .mouseRepeat(code: 0x68, rate: 20), .mouseRepeat(code: 0x69, rate: 20)], id: \.self) { a in
                            pick(a, current: action)
                        }
                    }
                    Section("Sensitivity") {
                        ForEach([ButtonAction.dpiCycleUp, .dpiCycleDown, .dpiUp, .dpiDown], id: \.self) { a in
                            pick(a, current: action)
                        }
                        Button("Sensitivity Clutch…", action: onClutch)
                    }
                    Section("Device") {
                        ForEach([ButtonAction.profileCycle, .scrollModeCycle, .hypershift], id: \.self) { a in
                            pick(a, current: action)
                        }
                    }
                    Divider()
                    Button("Keyboard Shortcut…", action: onRecord)
                    Button("Disable Button") { device.assign(.disabled, to: button) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(action.label).foregroundStyle(.secondary)
                Image(systemName: "lock.fill").foregroundStyle(.tertiary).help("Left click can’t be remapped")
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(isSelected ? Color.accentColor : .secondary.opacity(0.35)).frame(width: 7, height: 7)
                Text(button.label)
                if action != button.factoryAction {
                    Text("Custom").font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func pick(_ a: ButtonAction, current: ButtonAction) -> some View {
        Toggle(a.label, isOn: Binding(get: { current == a }, set: { if $0 { device.assign(a, to: button) } }))
    }
}

/// Captures one key combination via a local key monitor.
private struct KeyRecorderSheet: View {
    let button: MouseButton
    let done: (ButtonAction?) -> Void
    @State private var captured: ButtonAction?
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Press a key combination for \(button.label)").font(.headline)
            Text(captured?.label ?? "Waiting…")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .frame(minWidth: 200, minHeight: 48)
                .padding(.horizontal, 16)
                .glassEffect(in: .capsule)
            HStack {
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Assign") { done(captured) }
                    .buttonStyle(.glassProminent)
                    .disabled(captured == nil)
            }
        }
        .padding(28)
        .frame(width: 380)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                if let u = KeyNames.usage(forKeyCode: e.keyCode), !(e.keyCode == 53 && captured == nil && e.modifierFlags.isEmpty) {
                    captured = .key(modifiers: KeyNames.modifiers(e.modifierFlags), usage: u)
                    return nil
                }
                return e
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

private struct ClutchSheet: View {
    let initial: Int
    let done: (Int?) -> Void
    @State private var dpi = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sensitivity Clutch").font(.headline)
            Text("While held, the button drops sensitivity to this value — handy for precise aiming.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Slider(value: Binding(get: { LogScale.toSlider(dpi) }, set: { dpi = LogScale.fromSlider($0) }), in: 0...1)
                DPIField(value: $dpi, onCommit: {})
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Assign") { done(dpi) }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { dpi = initial }
    }
}
