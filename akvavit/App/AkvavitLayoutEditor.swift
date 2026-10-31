// SPDX-License-Identifier: GPL-3.0-or-later
//
// Madeira's on-screen controls editor, opened outside a game: from a game's
// settings (its layout) or from Settings › Controls (a type's default layout).
//
// Madeira's editor (TouchControlsOverlay, ContentView.swift) lives in its own window
// above everything, sheets included, and always edits the shared working copy
// (TouchControlsModel.shared, GestureZonesModel.shared). Here the working copy is
// set aside, the layout to edit loaded in its place and editing switched on. When
// the editor's Done ends editing, the result goes to the caller and the working copy
// comes back. Outside a game the overlay draws only in landscape; while this editor
// is open it draws in either orientation, as in a game session, over a dark
// backdrop with the title (hooks in TouchControlsOverlay, marked "Akvavit:").

import Combine
import SwiftUI

final class AkvavitLayoutEditor: ObservableObject {
    static let shared = AkvavitLayoutEditor()

    struct Layout {
        var controls: [TouchControl]
        var zones: [GestureZone]
        var layoutID: String?

        /// The shared working copy.
        static var current: Layout {
            Layout(controls: TouchControlsModel.shared.controls, zones: GestureZonesModel.shared.zones,
                   layoutID: TouchControlsModel.shared.layoutID)
        }
    }

    /// What is being edited ("Portal", "Custom Layout 1"); nil while closed.
    @Published private(set) var title: String?
    static var isOpen: Bool { shared.title != nil }
    /// A game's layout, not a named one (AkvavitGameControls.editsStayWithGame).
    private(set) var forGame = false

    private var saved: (layout: Layout, visible: Bool, sizeScale: Double)?
    private var onDone: ((Layout) -> Void)?
    private var watch: Set<AnyCancellable> = []

    /// Opens the editor with `layout`; `onDone` gets the edited layout. `forGame`: a
    /// game's layout, whose edits stay with the game.
    func open(title: String, layout: Layout, forGame: Bool = false, sizeScale: Double = 1,
              onDone: @escaping (Layout) -> Void) {
        let model = TouchControlsModel.shared
        guard self.title == nil, !model.editing, LibraryModel.shared.current == nil else { return }
        saved = (Layout.current, model.visible, model.sizeScale)
        self.onDone = onDone
        self.forGame = forGame
        self.title = title
        model.selected = nil
        GestureZonesModel.shared.selected = nil
        model.controls = layout.controls
        GestureZonesModel.shared.zones = layout.zones
        if ControlPresetsModel.enabled { model.layoutID = layout.layoutID }
        model.sizeScale = sizeScale
        model.visible = true
        // The controls window exists once a game has run; it re-frames on rotation.
        TouchControlsHost.attach()
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { _ in TouchControlsHost.attach() }
            .store(in: &watch)
        // @Published sends the new value before it is stored: finish on the next turn.
        model.$editing.dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in DispatchQueue.main.async { self?.close() } }
            .store(in: &watch)
        model.editing = true
        LogStore.shared.log("[akvavit-editor] editing \(title): \(layout.controls.count) controls")
    }

    private func close() {
        guard let saved else { return }
        let result = Layout.current
        watch.removeAll()
        let model = TouchControlsModel.shared
        model.selected = nil
        GestureZonesModel.shared.selected = nil
        model.controls = saved.layout.controls
        GestureZonesModel.shared.zones = saved.layout.zones
        if ControlPresetsModel.enabled { model.layoutID = saved.layout.layoutID }
        model.visible = saved.visible
        model.sizeScale = saved.sizeScale
        self.saved = nil
        LogStore.shared.log("[akvavit-editor] done with \(title ?? ""): \(result.controls.count) controls")
        title = nil
        forGame = false
        onDone?(result)
        onDone = nil
    }
}

/// The background of the editor outside a game, under the controls.
struct AkvavitEditorBackdrop: View {
    @ObservedObject private var editor = AkvavitLayoutEditor.shared

    var body: some View {
        if let title = editor.title {
            ZStack {
                Color.black.opacity(0.92)
                VStack(spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text("Hold the iPhone as when playing. Tap Done to save.").font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.45))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
