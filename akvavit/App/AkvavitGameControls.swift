// SPDX-License-Identifier: GPL-3.0-or-later
//
// A game type for each library game (User, Strategy, FPS), the pointer settings
// (Absolute, Relative or Touch, and the two sensitivities) and the on-screen layout
// kept per game, and each type's defaults.
//
// Madeira keeps a game's touch layout with the game (LibraryEntry.controls), but the
// pointer settings are global (InputSettings, Documents/madeira-input.json), so a
// change made in one game changed every game. Here:
//   - every type has defaults: pointer settings and an on-screen layout. A game
//     starts with its own saved values, otherwise with its type's defaults;
//   - the in-game menu changes only the running game. During a session
//     InputSettings holds the game's values without writing madeira-input.json, and
//     the global values come back when the session ends (also after a crash: the
//     file was never written);
//   - a game stores only what differs from its type's defaults (pointer values, and
//     a layout other than the type's), so it follows the type until it is changed;
//   - picking a type on the game's Controls page resets the game's pointer and
//     on-screen controls to that type's defaults.
// The defaults are built in below, and can be changed in Settings › Controls or
// taken from a game ("Use as defaults"), stored in
// Documents/akvavit-control-defaults.json. User's pointer defaults are the global
// pointer settings, and without a saved User layout its games use the shared one,
// as before types existed.
//
// Hooks in Madeira's files, marked "Akvavit:": LibraryEntry's fields, and
// LibraryModel.begin, saveCurrentProfile, finish and the Controls and Settings
// pages (Library.swift); InputSettings.save and TouchControlsOverlay
// (ContentView.swift); ControlPresetStore.builtIns (TouchControlPresets.swift).

import SwiftUI

enum AkvavitGameType: String, CaseIterable, Identifiable {
    case user, strategy, fps

    var id: String { rawValue }
    var title: String {
        switch self {
        case .user: "User"
        case .strategy: "Strategy"
        case .fps: "FPS"
        }
    }

    /// The stored value (LibraryEntry.gameType); nil and unknown values are User.
    init(_ stored: String?) { self = stored.flatMap(Self.init(rawValue:)) ?? .user }
    var stored: String? { self == .user ? nil : rawValue }
}

/// A type's defaults as changed by the user; nil fields keep the built-in ones.
struct AkvavitTypeDefaults: Codable, Equatable {
    var pointer: String?
    var sensAbs: Double?
    var sensRel: Double?
    /// The layout chosen in Settings › Controls (TouchControlPresets.swift's named
    /// layouts); "" = none.
    var layoutID: String?
    var controlsShown: Bool?
    /// A layout copy, as the first version stored it; made a named layout on load.
    var controls: [TouchControl]?
    var zones: [GestureZone]?
}

/// Documents/akvavit-control-defaults.json: the changed defaults, by type.
final class AkvavitControlDefaults: ObservableObject {
    static let shared = AkvavitControlDefaults()

    @Published var types: [String: AkvavitTypeDefaults] { didSet { save() } }

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("akvavit-control-defaults.json")
    }

    private init() {
        types = (try? Data(contentsOf: Self.url))
            .flatMap { try? JSONDecoder().decode([String: AkvavitTypeDefaults].self, from: $0) } ?? [:]
        // A layout copy becomes a named layout ("FPS layout"), which the type then uses.
        var migrated = false
        for (key, var value) in types {
            guard let controls = value.controls else { continue }
            let presets = ControlPresetsModel.shared
            if value.layoutID.flatMap({ presets.store.preset($0) }) == nil {
                let name = AkvavitGameControls.freeName("\(AkvavitGameType(key).title) layout")
                presets.change {
                    if case .created(let id) = $0.save(name: name, controls: controls, zones: value.zones ?? []) {
                        value.layoutID = id; return true
                    }
                    return false
                }
            }
            value.controls = nil; value.zones = nil
            types[key] = value
            migrated = true
        }
        if migrated { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(types) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }

    subscript(type: AkvavitGameType) -> AkvavitTypeDefaults {
        get { types[type.rawValue] ?? AkvavitTypeDefaults() }
        set { types[type.rawValue] = newValue == AkvavitTypeDefaults() ? nil : newValue }
    }
}

enum AkvavitGameControls {
    enum PointerMode: String, CaseIterable { case absolute, relative, touch }

    struct Pointer: Equatable {
        var mode: PointerMode
        var sensAbs: Double
        var sensRel: Double
    }

    struct Defaults {
        var pointer: Pointer
        /// The on-screen layout a game without its own starts with; nil keeps the
        /// shared one.
        var controls: [TouchControl]?
        var zones: [GestureZone]?
        var layoutID: String?
        var controlsShown: Bool
    }

    /// The user's Portal layout: a WASD stick, left and right click, E and Enter.
    static let fpsLayout = ControlPreset(
        id: "builtin.akvavit.fps", name: "FPS keyboard & mouse",
        controls: [
            TouchControl(id: UUID(uuidString: "6F1D2C1E-5A0B-4C61-9D0E-0A1F00000001")!,
                         nx: 0.110, ny: 0.840, action: .joystickWASD),
            TouchControl(id: UUID(uuidString: "6F1D2C1E-5A0B-4C61-9D0E-0A1F00000002")!,
                         nx: 0.782, ny: 0.811, action: .mouseLeft),
            TouchControl(id: UUID(uuidString: "6F1D2C1E-5A0B-4C61-9D0E-0A1F00000003")!,
                         nx: 0.878, ny: 0.733, action: .mouseRight),
            TouchControl(id: UUID(uuidString: "6F1D2C1E-5A0B-4C61-9D0E-0A1F00000004")!,
                         nx: 0.720, ny: 0.914, action: .key(0x45)),   // E
            TouchControl(id: UUID(uuidString: "6F1D2C1E-5A0B-4C61-9D0E-0A1F00000005")!,
                         nx: 0.905, ny: 0.592, action: .key(0x0D)),   // Enter
        ])

    /// Listed with Madeira's built-in layouts (ControlPresetStore.builtIns).
    static let builtInPresets = [fpsLayout]

    /// The defaults before any change. User's pointer is the global setting.
    static func builtInDefaults(for type: AkvavitGameType) -> Defaults {
        switch type {
        case .user:
            return Defaults(pointer: userPointer, controlsShown: false)
        case .strategy:
            return Defaults(pointer: Pointer(mode: .touch, sensAbs: 2.0, sensRel: 2.0), controlsShown: false)
        case .fps:
            // The relative sensitivity the user tuned for Portal; the layout as edited, if it was.
            let layout = ControlPresetStore.builtIns.first { $0.id == fpsLayout.id } ?? fpsLayout
            return Defaults(pointer: Pointer(mode: .relative, sensAbs: 2.0, sensRel: 6.0),
                            controls: layout.controls, zones: layout.zones ?? [], layoutID: fpsLayout.id,
                            controlsShown: true)
        }
    }

    /// The type's defaults: the built-in ones with the user's changes.
    static func defaults(for type: AkvavitGameType) -> Defaults {
        var d = builtInDefaults(for: type)
        let changed = AkvavitControlDefaults.shared[type]
        if type != .user {   // User's pointer defaults are the global settings
            if let mode = changed.pointer.flatMap(PointerMode.init(rawValue:)) { d.pointer.mode = mode }
            if let value = changed.sensAbs { d.pointer.sensAbs = value }
            if let value = changed.sensRel { d.pointer.sensRel = value }
        }
        if let id = changed.layoutID {
            if id.isEmpty {
                d.controls = nil; d.zones = nil; d.layoutID = nil
            } else if let preset = ControlPresetsModel.shared.store.preset(id) {   // a deleted one: the built-in default
                d.controls = preset.controls; d.zones = preset.zones ?? []; d.layoutID = preset.id
            }
        }
        if let shown = changed.controlsShown { d.controlsShown = shown }
        return d
    }

    /// `name`, or "name 2", "name 3", ...: one no layout has yet.
    static func freeName(_ name: String) -> String {
        let store = ControlPresetsModel.shared.store
        var candidate = ControlPresetStore.clean(name), n = 2
        while store.named(candidate) != nil { candidate = ControlPresetStore.clean("\(name) \(n)"); n += 1 }
        return candidate
    }

    /// The same controls, apart from their ids (Madeira gives loaded copies new ones).
    static func sameLayout(_ a: [TouchControl], _ az: [GestureZone], _ b: [TouchControl], _ bz: [GestureZone]) -> Bool {
        a.count == b.count && az.count == bz.count
            && zip(a, b).allSatisfy { var c = $0; c.id = $1.id; return c == $1 }
            && zip(az, bz).allSatisfy { var z = $0; z.id = $1.id; return z == $1 }
    }

    /// While a library session runs, InputSettings holds the game's values and must
    /// not write them to madeira-input.json (InputSettings.save).
    private(set) static var holdsInputFile = false
    /// The global values, kept while a session runs.
    private static var global: Pointer?
    /// In a game, or editing a game's layout from its settings, an edit of a named
    /// layout stays with the game (ControlPresetsModel.editingEnded) instead of
    /// changing the layout for every game and type that uses it.
    static var editsStayWithGame: Bool { holdsInputFile || AkvavitLayoutEditor.shared.forGame }
    /// User's pointer defaults: the global values.
    static var userPointer: Pointer { global ?? current() }

    private static func current() -> Pointer {
        let input = InputSettings.shared
        return Pointer(mode: input.touchMode ? .touch : (input.relative ? .relative : .absolute),
                       sensAbs: input.sensAbs, sensRel: input.sensRel)
    }

    private static func apply(_ pointer: Pointer) {
        let input = InputSettings.shared
        input.touchMode = pointer.mode == .touch
        input.relative = pointer.mode == .relative
        input.sensAbs = pointer.sensAbs
        input.sensRel = pointer.sensRel
    }

    /// The pointer a game starts with: its own values, or its type's.
    static func pointer(of entry: LibraryEntry) -> Pointer {
        let start = defaults(for: AkvavitGameType(entry.gameType)).pointer
        return Pointer(mode: entry.pointerMode.flatMap(PointerMode.init(rawValue:)) ?? start.mode,
                       sensAbs: entry.sensAbs ?? start.sensAbs, sensRel: entry.sensRel ?? start.sensRel)
    }

    /// Whether `controls` and `zones` are the type's default layout.
    private static func isDefaultLayout(_ controls: [TouchControl]?, _ zones: [GestureZone]?, of d: Defaults) -> Bool {
        guard let defaultControls = d.controls, let controls else { return false }
        return sameLayout(controls, zones ?? [], defaultControls, d.zones ?? [])
    }

    /// The game keeps only what differs from its type's defaults.
    private static func storeDifferences(_ pointer: Pointer, into entry: inout LibraryEntry) {
        let d = defaults(for: AkvavitGameType(entry.gameType))
        entry.pointerMode = pointer.mode == d.pointer.mode ? nil : pointer.mode.rawValue
        entry.sensAbs = pointer.sensAbs == d.pointer.sensAbs ? nil : pointer.sensAbs
        entry.sensRel = pointer.sensRel == d.pointer.sensRel ? nil : pointer.sensRel
        if isDefaultLayout(entry.controls, entry.zones, of: d) {
            entry.controls = nil; entry.zones = nil; entry.controlLayout = nil
        }
    }

    /// LibraryModel.begin, after Madeira has set up the game's own controls.
    static func begin(_ entry: LibraryEntry) {
        if !holdsInputFile { global = current() }
        holdsInputFile = true
        let type = AkvavitGameType(entry.gameType)
        let d = defaults(for: type)
        let pointer = pointer(of: entry)
        apply(pointer)
        // A game without its own layout starts with its type's (Madeira restores the
        // shared one when the session ends).
        var layout = "own"
        if entry.controls == nil {
            if let controls = d.controls {
                let model = TouchControlsModel.shared
                model.controls = controls
                GestureZonesModel.shared.selected = nil
                GestureZonesModel.shared.zones = d.zones ?? []
                if ControlPresetsModel.enabled { model.layoutID = d.layoutID }
                layout = "\(type.rawValue)-default"
            } else {
                layout = "shared"
            }
        }
        LogStore.shared.log("[akvavit-controls] \(entry.title): type=\(type.rawValue) pointer=\(pointer.mode.rawValue) "
                            + "sensAbs=\(pointer.sensAbs) sensRel=\(pointer.sensRel) "
                            + "saved=\(entry.pointerMode != nil || entry.sensAbs != nil || entry.sensRel != nil) "
                            + "layout=\(layout) shown=\(entry.touchControls)")
    }

    /// LibraryModel.saveCurrentProfile, after Madeira has written the controls.
    static func save(into entry: inout LibraryEntry) {
        guard holdsInputFile else { return }
        storeDifferences(current(), into: &entry)
    }

    /// LibraryModel.finish, after the game's profile is saved: the global values
    /// come back, and InputSettings writes its file again (with any other setting
    /// changed during the session).
    static func end() {
        AkvavitStickyKeys.shared.release()
        guard holdsInputFile else { return }
        holdsInputFile = false
        if let global { apply(global) }
        global = nil
    }

    /// A new type: the game's pointer and on-screen controls go back to the type's
    /// defaults at its next start.
    static func reset(_ entry: inout LibraryEntry, to type: AkvavitGameType) {
        entry.gameType = type.stored
        entry.pointerMode = nil; entry.sensAbs = nil; entry.sensRel = nil
        entry.controls = nil; entry.zones = nil; entry.controlLayout = nil
        entry.touchControls = defaults(for: type).controlsShown
    }

    /// The layout a game's editor starts with: its own, its type's, or the shared one.
    static func layout(of entry: LibraryEntry) -> AkvavitLayoutEditor.Layout {
        let d = defaults(for: AkvavitGameType(entry.gameType))
        if let controls = entry.controls {
            return .init(controls: controls, zones: entry.zones ?? [], layoutID: entry.controlLayout)
        }
        if let controls = d.controls { return .init(controls: controls, zones: d.zones ?? [], layoutID: d.layoutID) }
        return .current
    }

    /// The editor's result for a game, outside a session.
    static func setLayout(_ layout: AkvavitLayoutEditor.Layout, of entry: inout LibraryEntry) {
        entry.controls = layout.controls; entry.zones = layout.zones; entry.controlLayout = layout.layoutID
        entry.touchControls = true
        storeDifferences(pointer(of: entry), into: &entry)
    }

    /// "Use as defaults": the game's pointer and layout become its type's defaults. A
    /// layout no named one holds is saved as a new one, named after the game.
    static func useAsDefaults(_ entry: LibraryEntry) {
        let type = AkvavitGameType(entry.gameType)
        let pointer = pointer(of: entry)
        let layout = layout(of: entry)
        var changed = AkvavitControlDefaults.shared[type]
        if type == .user {
            apply(pointer)   // User's pointer defaults are the global settings
        } else {
            changed.pointer = pointer.mode.rawValue; changed.sensAbs = pointer.sensAbs; changed.sensRel = pointer.sensRel
        }
        let presets = ControlPresetsModel.shared
        if let id = layout.layoutID, let preset = presets.store.preset(id),
           sameLayout(layout.controls, layout.zones, preset.controls, preset.zones ?? []) {
            changed.layoutID = id
        } else if layout.controls.isEmpty && layout.zones.isEmpty {
            changed.layoutID = ""
        } else {
            let name = freeName(entry.title)
            presets.change {
                if case .created(let id) = $0.save(name: name, controls: layout.controls, zones: layout.zones) {
                    changed.layoutID = id; return true
                }
                return false
            }
        }
        changed.controlsShown = entry.touchControls
        AkvavitControlDefaults.shared[type] = changed
        LogStore.shared.log("[akvavit-controls] \(entry.title): now the \(type.rawValue) defaults")
    }

    /// "Reset to built-in defaults". User's pointer stays: it is the global setting.
    static func resetDefaults(_ type: AkvavitGameType) {
        AkvavitControlDefaults.shared[type] = AkvavitTypeDefaults()
    }
}

/// The game's Controls page: its type, its layout, and taking it as the type's defaults.
struct AkvavitGameTypeSection: View {
    @Binding var entry: LibraryEntry
    @State private var confirmDefaults = false

    var body: some View {
        let type = AkvavitGameType(entry.gameType)
        Section {
            Picker("Game type", selection: Binding(get: { type },
                                                   set: { AkvavitGameControls.reset(&entry, to: $0) })) {
                ForEach(AkvavitGameType.allCases) { Text($0.title).tag($0) }
            }
            Button("Edit layout") {
                let game = $entry
                AkvavitLayoutEditor.shared.open(title: entry.title, layout: AkvavitGameControls.layout(of: entry),
                                                forGame: true, sizeScale: entry.controlSize ?? 1) { layout in
                    AkvavitGameControls.setLayout(layout, of: &game.wrappedValue)
                    LibraryModel.shared.save(game.wrappedValue)
                }
            }
            Button("Use as defaults for \(type.title)") { confirmDefaults = true }
                .confirmationDialog("Use this game's controls as the defaults for \(type.title) games?",
                                    isPresented: $confirmDefaults, titleVisibility: .visible) {
                    Button("Use as defaults") { AkvavitGameControls.useAsDefaults(entry) }
                } message: {
                    Text("Its pointer settings and on-screen layout become the defaults. Games of this type that were not changed in the game use them.")
                }
        } footer: {
            Text("The type sets the pointer and on-screen controls the game starts with. Choosing a type resets them to its defaults. Changes made in the game stay with this game.")
        }
    }
}
