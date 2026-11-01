// SPDX-License-Identifier: GPL-3.0-or-later
//
// What Play does before the game starts: JIT on, Valve's client files in
// place, then the session with the game's settings. Once the session starts,
// the game screen comes up (RootView). What stops Play before that shows on
// the popup.

import AkvavitKit
import SwiftUI

@MainActor @Observable
final class PlayStart {
    /// What Play is doing before the session starts.
    private(set) var step: String?
    /// Why Play can't go ahead.
    private(set) var problem: String?

    var busy: Bool { step != nil }

    /// Why no game can start now, before Play is pressed.
    var blocked: String? {
        Session.shared.needsRestart
            ? "Windows can start once per app run. Close Akvavit and open it again to play."
            : nil
    }

    func clearProblem() { problem = nil }

    func play(_ game: Game) async {
        guard !busy, blocked == nil else { return }
        problem = nil
        defer { step = nil }
        if !JIT.shared.isOn {
            step = "Turning on JIT…"
            do {
                try await JIT.shared.enable()
            } catch {
                problem = "JIT didn't turn on. " + (JIT.shared.error ?? error.localizedDescription)
                return
            }
        }
        if !Steam.shared.clientReady {
            step = "Getting Steam's client files (once)…"
            do {
                try await Steam.shared.prepareClient()
            } catch {
                problem = "Steam's client files didn't download. " + error.localizedDescription
                return
            }
        }
        let settings = GameSettingsStore.shared[game.id]
        Session.shared.start(LaunchConfig(game: game, settings: settings, fitting: Self.fittingSize()))
    }

    /// A landscape Windows screen 768 pixels high, in the shape of this window
    /// (the display the app is on: the Duo's inner and outer ones differ).
    static func fittingSize() -> (width: Int, height: Int) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let size = scene?.effectiveGeometry.coordinateSpace.bounds.size ?? CGSize(width: 4, height: 3)
        let aspect = max(size.width, size.height) / max(min(size.width, size.height), 1)
        let width = Int((768 * aspect / 8).rounded()) * 8
        return (width, 768)
    }
}
