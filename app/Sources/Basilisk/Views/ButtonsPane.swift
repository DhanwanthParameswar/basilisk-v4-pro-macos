import SwiftUI
import AppKit

struct ButtonsPane: View {
    @Environment(DeviceManager.self) private var device
    @State private var selected: MouseButton? = .back
    @State private var recording: MouseButton?
    @State private var clutchFor: MouseButton?
    /// Which layer the rows below edit: the normal bindings, or the Hypershift layer.
    @State private var editingHypershift = false
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
                Section {
                    Picker("Layer", selection: $editingHypershift) {
                        Text("Normal").tag(false)
                        Text("Hypershift").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if editingHypershift {
                        Text("These bindings apply while a button set to Razer Hypershift is held — a second layer stored on the mouse. Unmapped buttons do nothing on this layer.")
                    } else {
                        Text("Your normal bindings. Switch to Hypershift to set a second layer that’s active while a Hypershift button is held.")
                    }
                }
                ForEach(groups, id: \.0) { group, buttons in
                    Section(group) {
                        ForEach(buttons) { b in
                            ButtonRow(button: b, isSelected: selected == b, hypershift: editingHypershift,
                                      onRecord: { recording = b }, onClutch: { clutchFor = b })
                                .id(b)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = b }
                                .onHover { if $0, Date.now > ignoreRowHoverUntil { selected = b } }
                        }
                    }
                }
                Section {
                    Button(editingHypershift ? "Clear Hypershift Layer" : "Restore Factory Assignments", role: .destructive) {
                        for b in MouseButton.allCases where b.isRemappable {
                            let target: ButtonAction = editingHypershift ? .disabled : b.factoryAction
                            if device.action(for: b, hypershift: editingHypershift) != target {
                                device.assign(target, to: b, hypershift: editingHypershift)
                            }
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
                if let action { device.assign(action, to: b, hypershift: editingHypershift) }
                recording = nil
            }
        }
        .sheet(item: $clutchFor) { b in
            ClutchSheet(initial: { if case .dpiClutch(let d) = device.action(for: b, hypershift: editingHypershift) { return d } else { return 400 } }()) { dpi in
                if let dpi { device.assign(.dpiClutch(dpi), to: b, hypershift: editingHypershift) }
                clutchFor = nil
            }
        }
    }
}

private struct ButtonRow: View {
    @Environment(DeviceManager.self) private var device
    let button: MouseButton
    let isSelected: Bool
    var hypershift: Bool = false
    let onRecord: () -> Void
    let onClutch: () -> Void

    /// On the Hypershift layer the baseline is "do nothing" rather than the factory action.
    private var defaultAction: ButtonAction { hypershift ? .disabled : button.factoryAction }

    var body: some View {
        let action = device.action(for: button, hypershift: hypershift)
        let software = device.softwareAction(for: button, hypershift: hypershift)
        LabeledContent {
            if button.isRemappable {
                Menu(software?.label ?? action.label) {
                    Button(hypershift ? "Not Mapped" : "Default (\(button.factoryAction.label))") {
                        device.assign(defaultAction, to: button, hypershift: hypershift)
                    }
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
                    Menu("System Actions") {
                        Section("Keyboard shortcuts, stored on the mouse") {
                            ForEach(SystemAction.allCases) { sa in
                                Toggle(sa.label, isOn: Binding(
                                    get: { action == sa.action && software == nil },
                                    set: { if $0 { device.assign(sa.action, to: button, hypershift: hypershift) } }))
                            }
                        }
                    }
                    Menu("System Gestures") {
                        Section("Run via the app — needs Accessibility, not stored on the mouse") {
                            ForEach(SoftwareAction.allCases) { sa in
                                Toggle(sa.label, isOn: Binding(
                                    get: { software == sa },
                                    set: { if $0 { device.assignSoftware(sa, to: button, hypershift: hypershift) } }))
                            }
                        }
                    }
                    Divider()
                    Menu("Function Key") {
                        // F13–F24 aren't on Mac keyboards, so they can't be recorded; nothing on macOS
                        // uses them, which makes them clash-free bindings for games and apps.
                        Section("F1–F12") {
                            ForEach(KeyNames.functionKeys.prefix(12), id: \.self) { pick(.key(modifiers: 0, usage: $0), current: action) }
                        }
                        Section("F13–F24") {
                            ForEach(KeyNames.functionKeys.dropFirst(12), id: \.self) { pick(.key(modifiers: 0, usage: $0), current: action) }
                        }
                    }
                    Button("Keyboard Shortcut…", action: onRecord)
                    Button("Disable Button") { device.assign(.disabled, to: button, hypershift: hypershift) }
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
                if action != defaultAction {
                    Text("Custom").font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func pick(_ a: ButtonAction, current: ButtonAction) -> some View {
        Toggle(a.label, isOn: Binding(get: { current == a }, set: { if $0 { device.assign(a, to: button, hypershift: hypershift) } }))
    }
}

/// Builds any key combination for a button. You can press a combo directly (works for
/// ordinary shortcuts, and for system-reserved ones like ⌘⇧4 when the HID event tap is
/// active), or build it by hand with the modifier toggles + key picker — which always
/// works, needs no permission, and can't be swallowed by the OS since nothing is typed.
private struct KeyRecorderSheet: View {
    let button: MouseButton
    let done: (ButtonAction?) -> Void
    @State private var modifiers: UInt8 = 0
    @State private var usage: UInt8 = 0
    @State private var tapActive = false
    @State private var recorder = SystemKeyRecorder()

    private static let modifierChips: [(UInt8, String)] = [(0x01, "⌃"), (0x04, "⌥"), (0x02, "⇧"), (0x08, "⌘")]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Set a shortcut for \(button.label)").font(.headline)

            Text(usage == 0 ? "Choose a key…" : KeyNames.describe(modifiers: modifiers, usage: usage))
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(usage == 0 ? .secondary : .primary)
                .frame(minWidth: 200, minHeight: 48)
                .padding(.horizontal, 16)
                .glassEffect(in: .capsule)

            // Modifier toggles
            HStack(spacing: 8) {
                ForEach(Self.modifierChips, id: \.0) { bit, symbol in
                    modifierChip(bit: bit, symbol: symbol)
                }
            }

            // Key picker
            Menu {
                ForEach(KeyNames.keyGroups, id: \.0) { title, keys in
                    Section(title) {
                        ForEach(keys, id: \.self) { u in
                            Button(KeyNames.name(u)) { usage = u }
                        }
                    }
                }
            } label: {
                Label(usage == 0 ? "Choose key" : "Key: \(KeyNames.name(usage))", systemImage: "chevron.down")
            }
            .menuStyle(.button)

            Text(tapActive
                 ? "Tip: you can also just press the combo — system shortcuts included."
                 : "Tip: you can press ordinary combos directly. Build reserved ones (⌘⇧4, etc.) above.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack {
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Clear") { modifiers = 0; usage = 0 }
                    .disabled(modifiers == 0 && usage == 0)
                Button("Assign") { done(.key(modifiers: modifiers, usage: usage)) }
                    .buttonStyle(.glassProminent)
                    .disabled(usage == 0)
            }
        }
        .padding(28)
        .frame(width: 380)
        // Live-press path: fills in whatever the OS lets through.
        .background(KeyCaptureView { if case let .key(m, u) = $0 { modifiers = m; usage = u } })
        .onAppear {
            recorder.onCapture = { if case let .key(m, u) = $0 { modifiers = m; usage = u } }
            tapActive = recorder.start()
        }
        .onDisappear { recorder.stop() }
    }

    @ViewBuilder
    private func modifierChip(bit: UInt8, symbol: String) -> some View {
        let on = modifiers & bit != 0
        let chip = Button(symbol) { modifiers ^= bit }
            .font(.system(.title3, design: .rounded))
            .frame(width: 44, height: 36)
        if on { chip.buttonStyle(.glassProminent) } else { chip.buttonStyle(.glass) }
    }
}

/// Records key combinations the normal responder chain never sees — including the
/// WindowServer's reserved shortcuts — via a HID-level `CGEventTap`. Active only while
/// the recorder sheet is open, and suppresses the captured event so e.g. a screenshot
/// isn't actually taken while you're assigning ⌘⇧4.
final class SystemKeyRecorder {
    var onCapture: ((ButtonAction) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Installs the tap. Returns false (and leaves the responder fallback in charge) when
    /// Accessibility permission is missing or the tap can't be created.
    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<SystemKeyRecorder>.fromOpaque(refcon)
                .takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Opens the Accessibility pane and prompts the user to grant access.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The tap can be disabled by the system; re-enable and pass the event through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let usage = KeyNames.usage(forKeyCode: keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        var mods: UInt8 = 0
        if flags.contains(.maskControl)   { mods |= 0x01 }
        if flags.contains(.maskShift)     { mods |= 0x02 }
        if flags.contains(.maskAlternate) { mods |= 0x04 }
        if flags.contains(.maskCommand)   { mods |= 0x08 }
        // A bare Escape should cancel the sheet, not be captured.
        if keyCode == 53 && mods == 0 { return Unmanaged.passUnretained(event) }

        let action = ButtonAction.key(modifiers: mods, usage: usage)
        DispatchQueue.main.async { self.onCapture?(action) }
        return nil   // swallow so the real shortcut doesn't fire while recording
    }
}

/// An NSView that grabs first-responder focus and reports the next key combination.
/// Overriding `performKeyEquivalent` is what lets ⌘-combinations through — a plain
/// `keyDown` monitor never sees them, because AppKit routes command keys to the
/// key-equivalent path first.
private struct KeyCaptureView: NSViewRepresentable {
    let onCapture: (ButtonAction) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let v = CaptureNSView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onCapture = onCapture
    }

    final class CaptureNSView: NSView {
        var onCapture: ((ButtonAction) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take focus once the sheet is on screen so keystrokes reach us.
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }

        /// Catches ⌘/system key-equivalents before the menu or default buttons do.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            capture(event)
        }

        override func keyDown(with event: NSEvent) {
            if !capture(event) { super.keyDown(with: event) }
        }

        /// Returns true when the event was consumed as a shortcut.
        @discardableResult
        private func capture(_ event: NSEvent) -> Bool {
            guard let usage = KeyNames.usage(forKeyCode: event.keyCode) else { return false }
            // A bare Escape cancels the sheet; let it fall through to the Cancel button.
            if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                return false
            }
            onCapture?(.key(modifiers: KeyNames.modifiers(event.modifierFlags), usage: usage))
            return true
        }
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
