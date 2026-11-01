// SPDX-License-Identifier: GPL-3.0-or-later
//
// The on-screen controls over a running game, in GameOverlay's window. Touches
// that begin on a control are the controls'; every other touch goes to the
// game. The (temporary) test menu opens in the same window, over the
// controls, and takes every touch while it shows.

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
        if runtime.layout == nil { runtime.use(TestLayoutChoice.layout) }
        let controller = controller ?? ControlsOverlayController()
        self.controller = controller
        GameOverlay.show(controller, touches: controller.controlTouches)
    }

    func hide() {
        ControlsRuntime.shared.releaseAll()
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
    private let canvas = UIHostingController(rootView: OverlayControls())
    private var menu: UIHostingController<TestGameMenu>?

    /// Only touches that begin on a control.
    var controlTouches: GameOverlay.Touches {
        .only { [weak self] point in
            guard let self else { return false }
            return self.input.owns(self.input.convert(point, from: nil))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The canvas draws; the input view above it takes the touches.
        canvas.safeAreaRegions = []
        canvas.view.backgroundColor = .clear
        canvas.view.isUserInteractionEnabled = false
        embed(canvas)
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

/// The chosen layout's controls, live.
private struct OverlayControls: View {
    private let runtime = ControlsRuntime.shared

    var body: some View {
        if let layout = runtime.layout {
            ControlsCanvas(layout: layout, safeArea: runtime.safeArea, inPlay: true) { runtime.state(of: $0) }
        }
    }
}

/// TEMPORARY: the layout over games, chosen in the test menu, until a game's
/// settings choose its layout.
@MainActor
enum TestLayoutChoice {
    private static let key = "akvavit.testLayout"

    static var layout: ControlLayout {
        UserDefaults.standard.string(forKey: key).flatMap { ControlLayoutStore.shared.layout(id: $0) }
            ?? BuiltInLayouts.touchAsMouse
    }

    static func choose(_ layout: ControlLayout) {
        UserDefaults.standard.set(layout.id, forKey: key)
        ControlsRuntime.shared.use(layout)
    }
}
