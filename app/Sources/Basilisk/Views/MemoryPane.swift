import SwiftUI

/// Onboard memory manager: the mouse's five profile slots (like Synapse's On-Board Memory),
/// which one is live, and how much flash is left.
struct MemoryPane: View {
    @Environment(DeviceManager.self) private var device

    private enum Prompt: Identifiable {
        case save(UInt8), rename(UInt8)
        var id: String {
            switch self { case .save(let s): "save\(s)"; case .rename(let s): "rename\(s)" }
        }
        var slot: UInt8 { switch self { case .save(let s), .rename(let s): s } }
        var isSave: Bool { if case .save = self { true } else { false } }
    }

    @State private var prompt: Prompt?
    @State private var nameDraft = ""
    @State private var pendingDelete: OnboardProfile?
    @State private var pendingOverwrite: OnboardProfile?

    var body: some View {
        Form {
            Section {
                ForEach(1...UInt8(OnboardProfile.slotCount), id: \.self) { slot in
                    SlotRow(slot: slot,
                            onSave: { startSave(slot) },
                            onRename: { startRename(slot) },
                            onDelete: { pendingDelete = device.profile(slot) })
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("The profile button on top of the mouse cycles through saved profiles, and its light shows the slot colour. The other panes always edit the active profile.")
            }
            .disabled(device.profileBusy)

            Section {
                LabeledContent("Saved per profile", value: "Sensitivity stages, polling rate, scroll mode, Smart-Reel, brightness, button assignments")
                LabeledContent("Shared by all profiles", value: "Lighting effects, scroll acceleration, lift-off, power")
            } header: {
                Text("What a profile holds")
            }

            if let s = device.storage {
                Section("Storage") {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: s.fraction)
                        HStack {
                            Text("\(Self.kb(s.used)) used").monospacedDigit()
                            Spacer()
                            Text("\(Self.kb(s.available)) free of \(Self.kb(s.total))").monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        if s.recyclable > 0 {
                            Text("\(Self.kb(s.recyclable)) is held by deleted items and is reclaimed when the memory is reorganised.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !device.supportsFullControl {
                Section {
                    Label("Over Bluetooth you can switch, rename and delete profiles. Saving settings into a slot needs the cable or the HyperSpeed dongle.",
                          systemImage: "dot.radiowaves.right")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            if device.profileBusy {
                ToolbarItem(placement: .primaryAction) { ProgressView().controlSize(.small) }
            }
        }
        .task { if device.profiles.isEmpty { await device.refreshProfiles() } }
        .alert(prompt.map { $0.isSave ? "Save to slot \($0.slot)" : "Rename profile" } ?? "",
               isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
               presenting: prompt) { p in
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button(p.isSave ? "Save" : "Rename") { commit(p) }
                .keyboardShortcut(.defaultAction)
        } message: { p in
            if p.isSave {
                Text("Copies the settings of \(device.profile(device.activeProfile)?.displayName ?? "the active profile") into slot \(p.slot).")
            }
        }
        .confirmationDialog("Replace \(pendingOverwrite?.displayName ?? "")?",
                            isPresented: Binding(get: { pendingOverwrite != nil }, set: { if !$0 { pendingOverwrite = nil } }),
                            presenting: pendingOverwrite) { p in
            Button("Replace") { promptSave(p.id, name: p.isDefault ? "" : p.name) }
        } message: { p in
            Text("Slot \(p.id)'s settings will be overwritten with the active profile's.")
        }
        .confirmationDialog("Delete \(pendingDelete?.displayName ?? "")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { p in
            Button("Delete", role: .destructive) { Task { await device.deleteProfile(p.id) } }
        } message: { p in
            Text(p.id == device.activeProfile
                 ? "It's the active profile, so the mouse switches back to the default profile. This can't be undone."
                 : "Slot \(p.id) is cleared on the mouse. This can't be undone.")
        }
    }

    private func startSave(_ slot: UInt8) {
        if let existing = device.profile(slot) {
            pendingOverwrite = existing
        } else {
            promptSave(slot, name: "Profile \(slot)")
        }
    }

    private func promptSave(_ slot: UInt8, name: String) {
        if slot == 1 {   // the default profile has no name; nothing to ask
            Task { await device.saveCurrentSettings(toSlot: 1, name: "") }
            return
        }
        nameDraft = name
        prompt = .save(slot)
    }

    private func startRename(_ slot: UInt8) {
        nameDraft = device.profile(slot)?.name ?? ""
        prompt = .rename(slot)
    }

    private func commit(_ p: Prompt) {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            switch p {
            case .save(let s): await device.saveCurrentSettings(toSlot: s, name: name.isEmpty ? "Profile \(s)" : name)
            case .rename(let s): await device.renameProfile(s, to: name)
            }
        }
    }

    static func kb(_ bytes: Int) -> String {
        bytes >= 1024 ? "\(bytes / 1024) KB" : "\(bytes) B"
    }
}

private struct SlotRow: View {
    @Environment(DeviceManager.self) private var device
    let slot: UInt8
    let onSave: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var profile: OnboardProfile? { device.profile(slot) }
    private var isActive: Bool { device.activeProfile == slot }
    private var color: RGB { profile?.color ?? OnboardProfile.defaultColors[slot] ?? .white }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.color.opacity(profile == nil ? 0.25 : 1))
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                .frame(width: 14, height: 14)
                .shadow(color: isActive ? color.color.opacity(0.8) : .clear, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile?.displayName ?? "Empty")
                        .font(.body.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(profile == nil ? .secondary : .primary)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(slot == 1 ? "Slot 1 · Default · White" : "Slot \(slot) · \(OnboardProfile(id: slot, name: "", color: color).colorName)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let profile {
                if !isActive {
                    Button("Activate") { Task { await device.activateProfile(slot) } }
                }
                if !(profile.isDefault && isActive) {   // nothing to offer on the live default profile
                Menu {
                    Button("Save Active Settings Here…", action: onSave)
                        .disabled(isActive || !device.supportsFullControl)
                    if !profile.isDefault {
                        Button("Rename…", action: onRename)
                        Divider()
                        Button("Delete…", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(profile.displayName)")
                }
            } else {
                Button("Save Active Settings Here…", action: onSave)
                    .disabled(!device.supportsFullControl)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private extension OnboardProfile {
    init(id: UInt8, name: String, color: RGB) { self.init(id: id, name: name, color: color, header: nil) }
}
