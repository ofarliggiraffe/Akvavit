// SPDX-License-Identifier: GPL-3.0-or-later
//
// Settings › Controls, in place of Madeira's Settings › Pointer section:
//   - Layouts: the named on-screen layouts (Madeira's, TouchControlPresets.swift).
//     Every layout can be edited (in Madeira's editor, AkvavitLayoutEditor.swift).
//     The user's own can also be renamed, duplicated and deleted; a built-in one can
//     be duplicated and reset to how it ships (its edits are kept apart, in
//     AkvavitBuiltInLayouts, and laid over Madeira's);
//   - User, Strategy, FPS: each game type's defaults (AkvavitGameControls.swift):
//     pointer settings, whether the on-screen controls show, and which layout.
// User's pointer defaults are the global settings, so its page shows Madeira's own
// pointer controls (LibraryPointerSettings). Nothing here is reachable from a game.

import SwiftUI

/// The user's edits of the built-in layouts, in Documents/akvavit-builtin-layouts.json.
/// ControlPresetStore.builtIns lays them over the layouts as shipped.
final class AkvavitBuiltInLayouts: ObservableObject {
    static let shared = AkvavitBuiltInLayouts()

    struct Edit: Codable, Equatable {
        var controls: [TouchControl]
        var zones: [GestureZone]?
    }

    @Published private(set) var edits: [String: Edit] { didSet { save() } }

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("akvavit-builtin-layouts.json")
    }

    private init() {
        edits = (try? Data(contentsOf: Self.url))
            .flatMap { try? JSONDecoder().decode([String: Edit].self, from: $0) } ?? [:]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(edits) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }

    /// ControlPresetStore.builtIns: the layouts as shipped, with the user's edits.
    static func applied(_ presets: [ControlPreset]) -> [ControlPreset] {
        presets.map { preset in
            guard let edit = shared.edits[preset.id] else { return preset }
            var edited = preset
            edited.controls = edit.controls
            edited.zones = edit.zones
            return edited
        }
    }

    static func isEdited(_ id: String) -> Bool { shared.edits[id] != nil }

    func set(_ id: String, controls: [TouchControl], zones: [GestureZone]) {
        edits[id] = Edit(controls: controls, zones: zones.isEmpty ? nil : zones)
    }

    func reset(_ id: String) { edits[id] = nil }
}

struct AkvavitControlsSettingsSection: View {
    private enum Page: Hashable, Identifiable {
        case layouts, type(AkvavitGameType)
        var id: Self { self }
    }
    @State private var open: Page?

    var body: some View {
        Section {
            row("Layouts") { open = .layouts }
            ForEach(AkvavitGameType.allCases) { type in row(type.title) { open = .type(type) } }
        } header: {
            Text("Controls")
        } footer: {
            Text("Layouts are the on-screen controls. Each game type starts with its pointer settings and one of the layouts. A game's type is set on its Controls page; changes made in a game stay with that game.")
        }
        .sheet(item: $open) { page in
            NavigationStack {
                switch page {
                case .layouts: AkvavitLayoutsPage()
                case .type(let type): AkvavitTypeDefaultsPage(type: type)
                }
            }
        }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent(title) {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
}

/// The named layouts: the user's, then the built-in ones.
struct AkvavitLayoutsPage: View {
    @ObservedObject private var presets = ControlPresetsModel.shared
    @ObservedObject private var builtInEdits = AkvavitBuiltInLayouts.shared
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: ControlPreset?
    @State private var newName = ""
    @State private var deleting: ControlPreset?
    @State private var resetting: ControlPreset?
    @State private var problem: String?

    private var builtIns: [ControlPreset] { presets.available.filter { ControlPresetStore.isBuiltIn($0.id) } }

    var body: some View {
        Form {
            Section {
                ForEach(presets.store.user) { preset in
                    Button { edit(preset) } label: {
                        LabeledContent(preset.name) { Text(count(preset)).foregroundStyle(.secondary) }
                    }
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button("Edit", systemImage: "slider.horizontal.3") { edit(preset) }
                        Button("Rename", systemImage: "pencil") { newName = preset.name; renaming = preset }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(preset) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = preset }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { deleting = preset } }
                }
                Button("New layout", systemImage: "plus") { create() }
            } header: {
                Text("Your layouts")
            } footer: {
                Text("Tap a layout to edit it; touch and hold for more. Hold the iPhone as when playing, and tap Done to save.")
            }
            if !builtIns.isEmpty {
                Section {
                    ForEach(builtIns) { preset in
                        let edited = AkvavitBuiltInLayouts.isEdited(preset.id)
                        HStack {
                            Button { edit(preset) } label: {
                                LabeledContent(preset.name) {
                                    Text(edited ? "Edited" : count(preset)).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            if edited {
                                Button("Reset") { resetting = preset }
                                    .buttonStyle(.borderless)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "slider.horizontal.3") { edit(preset) }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(preset) }
                            if edited {
                                Button("Reset to original", systemImage: "arrow.uturn.backward", role: .destructive) {
                                    resetting = preset
                                }
                            }
                        }
                    }
                } header: {
                    Text("Built in")
                } footer: {
                    Text("Built-in layouts can be edited too. Reset brings one back to how it ships.")
                }
            }
        }
        .navigationTitle("Layouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .alert("Rename layout", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let renaming { rename(renaming, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deleting { _ = presets.delete(deleting.id) } }
        } message: {
            Text("Game types that use it go back to their built-in layout. Games keep their own copies.")
        }
        .confirmationDialog("Reset \(resetting?.name ?? "") to the original?",
                            isPresented: Binding(get: { resetting != nil }, set: { if !$0 { resetting = nil } }),
                            titleVisibility: .visible) {
            Button("Reset", role: .destructive) { if let resetting { builtInEdits.reset(resetting.id) } }
        }
        .alert("Layouts", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    private func count(_ preset: ControlPreset) -> String {
        let n = preset.controls.count + (preset.zones?.count ?? 0)
        return n == 1 ? "1 control" : "\(n) controls"
    }

    /// The user's layouts: Madeira's editor writes the edits back itself
    /// (editingEnded), and so does this. A built-in's edits go to AkvavitBuiltInLayouts,
    /// unless nothing changed (a built-in is laid out for the screen when it opens).
    private func edit(_ preset: ControlPreset) {
        let id = preset.id
        let builtIn = ControlPresetStore.isBuiltIn(id)
        let opened = AkvavitLayoutEditor.Layout(
            controls: builtIn ? ControlPresetStore.layout(of: preset, screen: ControlPresetsModel.currentScreen())
                              : preset.controls,
            zones: preset.zones ?? [], layoutID: id)
        AkvavitLayoutEditor.shared.open(title: preset.name, layout: opened) { edited in
            if builtIn {
                guard !AkvavitGameControls.sameLayout(edited.controls, edited.zones, opened.controls, opened.zones) else { return }
                AkvavitBuiltInLayouts.shared.set(id, controls: edited.controls, zones: edited.zones)
            } else {
                ControlPresetsModel.shared.change { $0.overwrite(id: id, controls: edited.controls, zones: edited.zones) }
            }
        }
    }

    private func create() {
        let name = AkvavitGameControls.freeName("Custom Layout")
        var created: ControlPreset?
        presets.change {
            guard case .created(let id) = $0.save(name: name, controls: []) else { return false }
            created = $0.preset(id)
            return true
        }
        if let created { edit(created) } else { problem = "The layout could not be saved." }
    }

    private func duplicate(_ preset: ControlPreset) {
        let name = AkvavitGameControls.freeName("\(preset.name) copy")
        let ok = presets.change {
            if case .created = $0.save(name: name, controls: preset.controls, zones: preset.zones ?? []) { return true }
            return false
        }
        if !ok { problem = "The layout could not be saved." }
    }

    /// Madeira's layouts have no rename: the layout is saved again under its own id.
    private func rename(_ preset: ControlPreset, to name: String) {
        let clean = ControlPresetStore.clean(name)
        guard !clean.isEmpty, clean != preset.name else { return }
        if let other = presets.store.named(clean), other.id != preset.id {
            problem = "A layout named \u{201C}\(other.name)\u{201D} already exists."; return
        }
        presets.change {
            guard $0.delete(id: preset.id) else { return false }
            _ = $0.save(name: clean, controls: preset.controls, zones: preset.zones ?? [], newID: { preset.id })
            return true
        }
    }
}

struct AkvavitTypeDefaultsPage: View {
    let type: AkvavitGameType
    @ObservedObject private var store = AkvavitControlDefaults.shared
    @ObservedObject private var presets = ControlPresetsModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private var defaults: AkvavitGameControls.Defaults { AkvavitGameControls.defaults(for: type) }

    /// The type's pointer defaults; values equal to the built-in ones are not stored.
    private var pointer: Binding<AkvavitGameControls.Pointer> {
        Binding(get: { defaults.pointer }, set: { new in
            let builtIn = AkvavitGameControls.builtInDefaults(for: type).pointer
            var changed = store[type]
            changed.pointer = new.mode == builtIn.mode ? nil : new.mode.rawValue
            changed.sensAbs = new.sensAbs == builtIn.sensAbs ? nil : new.sensAbs
            changed.sensRel = new.sensRel == builtIn.sensRel ? nil : new.sensRel
            store[type] = changed
        })
    }

    /// The chosen layout; "" = none. Choosing the built-in default stores nothing.
    private var layout: Binding<String> {
        Binding(get: { defaults.controls == nil ? "" : (defaults.layoutID ?? "") }, set: { id in
            let builtIn = AkvavitGameControls.builtInDefaults(for: type).layoutID ?? ""
            store[type].layoutID = id == builtIn ? nil : id
        })
    }

    var body: some View {
        Form {
            Section("Pointer") {
                if type == .user { LibraryPointerSettings() } else { AkvavitPointerControls(pointer: pointer) }
            }
            Section {
                Picker("Layout", selection: layout) {
                    Text(type == .user ? "Shared" : "None").tag("")
                    ForEach(presets.available) { Text($0.name).tag($0.id) }
                }
                Toggle("Show on-screen controls", isOn: Binding(get: { defaults.controlsShown },
                                                                set: { store[type].controlsShown = $0 }))
            } header: {
                Text("On-screen controls")
            } footer: {
                Text(type == .user && defaults.controls == nil
                     ? "\u{201C}Shared\u{201D}: a User game without a layout of its own uses the shared one, as before game types. Layouts are made and edited under Settings › Controls › Layouts."
                     : "Layouts are made and edited under Settings › Controls › Layouts.")
            }
            Section {
                Button("Reset to built-in defaults", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Changes here are saved right away. Games of this type use these defaults unless they were changed in the game; choosing the type again on a game's Controls page resets the game. Nothing in a game changes these defaults.")
            }
        }
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .confirmationDialog("Reset \(type.title) to the built-in defaults?", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Reset", role: .destructive) { AkvavitGameControls.resetDefaults(type) }
        }
    }
}

/// The pointer controls of LibraryPointerSettings (Library.swift), for a type's defaults.
struct AkvavitPointerControls: View {
    @Binding var pointer: AkvavitGameControls.Pointer

    var body: some View {
        Picker("Pointer mode", selection: $pointer.mode) {
            Text("Absolute").tag(AkvavitGameControls.PointerMode.absolute)
            Text("Relative").tag(AkvavitGameControls.PointerMode.relative)
            Text("Touch").tag(AkvavitGameControls.PointerMode.touch)
        }
        .pickerStyle(.segmented)
        Text(pointer.mode == .touch ? "Tap the screen to position and click. Hold and move to drag. Two fingers: right click or scroll."
             : (pointer.mode == .relative ? "Drag to send relative mouse movement for mouse-look. Tap to click." : "Drag the pointer like a trackpad. Tap to click."))
            .font(.caption).foregroundStyle(.secondary)
        LabeledContent("Touch sensitivity") {
            Slider(value: pointer.mode == .relative ? $pointer.sensRel : $pointer.sensAbs, in: 0.1...8)
        }
    }
}
