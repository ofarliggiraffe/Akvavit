// SPDX-License-Identifier: GPL-3.0-or-later
//
// The on-screen controls over a running game, in GameOverlay's window. Touches
// that begin on a control are the controls'; every other touch goes to the
// game. The (temporary) test menu opens in the same window, over the
// controls, and takes every touch while it shows. The loading screen is in
// this window too, under the controls: above everything of Windows' screen,
// so nothing of it shows through however early it appears. While it covers
// the game it takes only touches on its button.

import AkvavitKit
import SwiftUI
import UIKit

@MainActor
final class ControlsOverlay {
    static let shared = ControlsOverlay()

    private var controller: ControlsOverlayController?

    /// Shows the controls over the game (the chosen layout).
    func show() {
        let runtime = ControlsRuntime.shared
        if runtime.layout == nil { runtime.use(GameLayoutChoice.layout) }
        let controller = controller ?? ControlsOverlayController()
        self.controller = controller
        GameOverlay.show(controller, touches: controller.controlTouches)
    }

    func hide() {
        ControlsRuntime.shared.releaseAll()
        TextBridge.shared.hide()
        GameOverlay.hide()
        controller = nil
    }

    func showMenu() {
        if controller == nil || !GameOverlay.isShown { show() }
        controller?.openMenu()
    }
}

final class ControlsOverlayController: UIViewController {
    private let input = ControlsInputView()
    private let loading = UIHostingController(rootView: OverlayLoading())
    private let canvas = UIHostingController(rootView: OverlayControls())
    private let performance = UIHostingController(rootView: PerformanceBar())
    private var menu: UIHostingController<TestGameMenu>?

    /// Only touches that begin on a control (on the loading screen's button
    /// while it covers the game).
    var controlTouches: GameOverlay.Touches {
        .only { [weak self] point in
            guard let self else { return false }
            if StartProgress.shared.covers { return LoadingTouches.button?.contains(point) ?? false }
            return self.input.owns(self.input.convert(point, from: nil))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loading.view.backgroundColor = .clear
        embed(loading)
        // The canvas draws; the input view above it takes the touches.
        canvas.safeAreaRegions = []
        canvas.view.backgroundColor = .clear
        canvas.view.isUserInteractionEnabled = false
        embed(canvas)
        // Information only: above the controls, never touched.
        performance.view.backgroundColor = .clear
        performance.view.isUserInteractionEnabled = false
        embed(performance)
        input.frame = view.bounds
        input.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(input)
    }

    func openMenu() {
        guard menu == nil else { return }
        ControlsRuntime.shared.releaseAll()
        let menu = UIHostingController(rootView: TestGameMenu { [weak self] in self?.closeMenu() })
        menu.view.backgroundColor = .clear
        embed(menu)
        self.menu = menu
        GameOverlay.setTouches(.all)
    }

    func closeMenu() {
        guard let menu else { return }
        menu.willMove(toParent: nil)
        menu.view.removeFromSuperview()
        menu.removeFromParent()
        self.menu = nil
        GameOverlay.setTouches(controlTouches)
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    // As the game screen below: nothing of the system over the game.
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}

/// The loading screen while it covers the game; it fades out as the game shows.
private struct OverlayLoading: View {
    private let progress = StartProgress.shared
    private let session = Session.shared

    var body: some View {
        ZStack {
            if progress.covers {
                LoadingScreen(game: game, title: game?.name ?? session.config?.displayName ?? "")
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.5), value: progress.covers)
    }

    /// From the Play tap; for a start from the test screens, from the session.
    private var game: Game? {
        if let game = progress.game { return game }
        guard case .steam(let appID, _) = session.config?.program else { return nil }
        return Games.shared.game("steam:\(appID)")
    }
}

/// The chosen layout's controls, live.
private struct OverlayControls: View {
    private let runtime = ControlsRuntime.shared

    var body: some View {
        // Not over the loading screen: the controls come with the game.
        if let layout = runtime.layout, !StartProgress.shared.covers {
            ControlsCanvas(layout: layout, area: runtime.area, inPlay: true) { runtime.state(of: $0) }
        }
    }
}

/// The layout over a game: the one its Game settings choose (the default
/// layout, as you may have changed it, when none or when that layout was
/// deleted). A start from the test screens has no game: Touch as mouse. The
/// test menu's choice is saved as the game's too.
@MainActor
enum GameLayoutChoice {
    static var layout: ControlLayout {
        let store = ControlLayoutStore.shared
        guard let game = StartProgress.shared.game else { return store.layout(id: BuiltInLayouts.touchAsMouse.id)! }
        return GameSettingsStore.shared[game.id].controlLayout.flatMap { store.layout(id: $0) }
            ?? store.layout(id: BuiltInLayouts.gameDefault.id)!
    }

    static func choose(_ layout: ControlLayout) {
        if let game = StartProgress.shared.game {
            GameSettingsStore.shared[game.id].controlLayout = layout.id == BuiltInLayouts.gameDefault.id ? nil : layout.id
        }
        ControlsRuntime.shared.use(layout)
    }
}
