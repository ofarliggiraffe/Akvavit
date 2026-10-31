// SPDX-License-Identifier: GPL-3.0-or-later
//
// A game type for each library game (User, Strategy, FPS), and the pointer settings
// (Absolute, Relative or Touch, and the two sensitivities) kept per game.
//
// Madeira keeps a game's touch layout with the game (LibraryEntry.controls), but the
// pointer settings are global (InputSettings, Documents/madeira-input.json), so a
// change made in one game changed every game. Here:
//   - every type has defaults. A game starts with its own saved values, otherwise
//     with its type's defaults;
//   - the in-game menu changes only the running game. During a session
//     InputSettings holds the game's values without writing madeira-input.json, and
//     the global values come back when the session ends (also after a crash: the
//     file was never written);
//   - a game stores only the values that differ from its type's defaults, so it
//     follows the type until it is changed;
//   - picking a type on the game's Controls page resets the game's pointer and
//     on-screen controls to that type's defaults.
// User's defaults are the global pointer settings (Settings › Pointer) and the
// shared on-screen layout, as before types existed. Strategy's and FPS's are built
// in below for now; a settings page for every type's defaults comes later.
//
// Hooks in Madeira's files, marked "Akvavit:": LibraryEntry's fields, and
// LibraryModel.begin, saveCurrentProfile, finish and the Controls and Settings
// pages (Library.swift); InputSettings.save (ContentView.swift);
// ControlPresetStore.builtIns (TouchControlPresets.swift).

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

enum AkvavitGameControls {
    enum PointerMode: String { case absolute, relative, touch }

    struct Pointer: Equatable {
        var mode: PointerMode
        var sensAbs: Double
        var sensRel: Double
    }

    struct Defaults {
        var pointer: Pointer
        /// The on-screen layout a game without its own starts with; nil keeps the
        /// shared one (User).
        var layout: ControlPreset?
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

    /// `user`: the global values, which are User's pointer defaults.
    static func defaults(for type: AkvavitGameType, user: Pointer) -> Defaults {
        switch type {
        case .user:
            Defaults(pointer: user, layout: nil, controlsShown: false)
        case .strategy:
            Defaults(pointer: Pointer(mode: .touch, sensAbs: 2.0, sensRel: 2.0), layout: nil, controlsShown: false)
        case .fps:
            // The relative sensitivity the user tuned for Portal.
            Defaults(pointer: Pointer(mode: .relative, sensAbs: 2.0, sensRel: 6.0), layout: fpsLayout, controlsShown: true)
        }
    }

    /// While a library session runs, InputSettings holds the game's values and must
    /// not write them to madeira-input.json (InputSettings.save).
    private(set) static var holdsInputFile = false
    /// The global values, kept while a session runs.
    private static var global: Pointer?

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

    /// LibraryModel.begin, after Madeira has set up the game's own controls.
    static func begin(_ entry: LibraryEntry) {
        if !holdsInputFile { global = current() }
        holdsInputFile = true
        let type = AkvavitGameType(entry.gameType)
        let start = defaults(for: type, user: global ?? current())
        let pointer = Pointer(mode: entry.pointerMode.flatMap(PointerMode.init(rawValue:)) ?? start.pointer.mode,
                              sensAbs: entry.sensAbs ?? start.pointer.sensAbs,
                              sensRel: entry.sensRel ?? start.pointer.sensRel)
        apply(pointer)
        // A game without its own layout starts with its type's (Madeira restores the
        // shared one when the session ends).
        var layout = "own"
        if entry.controls == nil {
            if let preset = start.layout {
                let controls = TouchControlsModel.shared
                controls.controls = preset.controls
                GestureZonesModel.shared.selected = nil
                GestureZonesModel.shared.zones = preset.zones ?? []
                if ControlPresetsModel.enabled { controls.layoutID = preset.id }
                layout = preset.id
            } else {
                layout = "shared"
            }
        }
        LogStore.shared.log("[akvavit-controls] \(entry.title): type=\(type.rawValue) pointer=\(pointer.mode.rawValue) "
                            + "sensAbs=\(pointer.sensAbs) sensRel=\(pointer.sensRel) "
                            + "saved=\(entry.pointerMode != nil || entry.sensAbs != nil || entry.sensRel != nil) "
                            + "layout=\(layout) shown=\(entry.touchControls)")
    }

    /// LibraryModel.saveCurrentProfile: the game keeps the pointer values that
    /// differ from its type's defaults.
    static func save(into entry: inout LibraryEntry) {
        guard holdsInputFile, let global else { return }
        let start = defaults(for: AkvavitGameType(entry.gameType), user: global).pointer
        let now = current()
        entry.pointerMode = now.mode == start.mode ? nil : now.mode.rawValue
        entry.sensAbs = now.sensAbs == start.sensAbs ? nil : now.sensAbs
        entry.sensRel = now.sensRel == start.sensRel ? nil : now.sensRel
    }

    /// LibraryModel.finish, after the game's profile is saved: the global values
    /// come back, and InputSettings writes its file again (with any other setting
    /// changed during the session).
    static func end() {
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
        entry.touchControls = defaults(for: type, user: current()).controlsShown
    }

    /// Settings › Pointer's footer.
    static let settingsFooter = "The defaults for games of type User. Each game keeps its own pointer settings from the in-game menu."
}

/// The game's Controls page: its type.
struct AkvavitGameTypeSection: View {
    @Binding var entry: LibraryEntry

    var body: some View {
        Section {
            Picker("Game type", selection: Binding(get: { AkvavitGameType(entry.gameType) },
                                                   set: { AkvavitGameControls.reset(&entry, to: $0) })) {
                ForEach(AkvavitGameType.allCases) { Text($0.title).tag($0) }
            }
        } footer: {
            Text("Sets the pointer and on-screen controls the game starts with. Choosing a type resets them to its defaults. Changes made in the game stay with this game.")
        }
    }
}
