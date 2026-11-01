// SPDX-License-Identifier: GPL-3.0-or-later
//
// AkvavitKit: Akvavit's engine layer. It runs Madeira's engine (FEX, Wine,
// DXMT, Madeira Dock, SwiftSteam) and has no interface code of its own: the app
// reads its models and calls its methods, so the interface can change freely.
// Madeira's engine files are compiled in unchanged (project.yml).

import Foundation

@MainActor
public enum AkvavitEngine {
    private static var started = false

    /// Once, when the app starts, before any window. Leftovers of an earlier
    /// run are tidied, and the JIT VPN is set as the settings ask.
    public static func start() {
        guard !started else { return }
        started = true
        jit_install_trap_handler()
        DeviceDiagnostics.logStartup()
        // Madeira Dock: a sign-in transfer an earlier run left behind goes.
        if wine_process_is_running() == 0 { MadeiraDock.cleanup() }
        DockOffline.begin()
        // Dock's Reset takes the Visual C++ markers from the bundled prefix template.
        DockReset.baselineProvider = { DockReset.templateRegistry { madeira_extract_prefix_tgz($0, $1) } }
        JITNetworkShortcut.shared.restoreLeftover()
    }
}
