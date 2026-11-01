// SPDX-License-Identifier: GPL-3.0-or-later
//
// GameOverlay: a window above the game's picture for the interface to draw in
// during a session (a menu, on-screen controls). The picture sits above the
// app's own window (GameLayerHost), so anything drawn there is hidden; this
// window is above both. It never becomes the key window.
//
// Touches: a menu takes them all (the game gets none while it shows). For
// content spread over the game (on-screen controls), the interface says which
// points are its own; every other touch goes to the game. SwiftUI cannot tell
// this by itself: a hit on a SwiftUI button reports the same view as a hit on
// empty space.

import UIKit

@MainActor
public enum GameOverlay {
    public enum Touches {
        /// Every touch goes to the overlay (a menu).
        case all
        /// Only touches at points for which this returns true (in the
        /// overlay's coordinates); the rest go to the game.
        case only((CGPoint) -> Bool)
    }

    private static var window: OverlayWindow?

    /// Shows `controller`'s view over the game, filling the display. Replaces
    /// what was shown before. Give the view a clear background.
    public static func show(_ controller: UIViewController, touches: Touches = .all) {
        guard let scene = GameLayerHost.shared.window?.windowScene else { return }
        let overlay = window ?? OverlayWindow(windowScene: scene)
        overlay.windowLevel = .normal + 1
        overlay.backgroundColor = .clear
        overlay.touches = touches
        controller.view.backgroundColor = .clear
        overlay.rootViewController = controller
        overlay.isHidden = false
        window = overlay
    }

    /// Changes which touches the overlay takes, keeping what it shows.
    public static func setTouches(_ touches: Touches) {
        window?.touches = touches
    }

    public static func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
    }

    public static var isShown: Bool { window?.isHidden == false }
}

private final class OverlayWindow: UIWindow {
    var touches: GameOverlay.Touches = .all

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if case .only(let isOwn) = touches, !isOwn(point) { return nil }
        return super.hitTest(point, with: event)
    }

    override var canBecomeKey: Bool { false }
}
