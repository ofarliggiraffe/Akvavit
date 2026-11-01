// SPDX-License-Identifier: GPL-3.0-or-later
//
// Starting a Steam game through Madeira Dock. Dock (dockhost.exe, on Windows'
// desktop) loads Valve's own client library, signs in with the account's
// token and asks Valve's client to start the game; Valve's client decides.
//
// Before Wine starts, the app hands Dock a one-use sign-in transfer and the
// game to start (MadeiraDock), and prepares the game's one-time installs from
// its Steam install script (DockInstallers, run first in the same session).

import Foundation

@MainActor
enum DockStart {
    struct Prepared {
        var environment: [String: String?]
        /// This session runs only the one-time installs; the game starts in
        /// the next app run (they and the game do not fit in one session).
        var installsOnly: Bool
        /// One-time installs run first.
        var installs: Bool
        /// The game's folder, as a Windows path (the loading screen's "game is up").
        var gameFolder: String
    }

    /// Every variable a Dock start sets: cleared for other sessions.
    static let variables = ["MADEIRA_DOCK_SESSION", "MADEIRA_CAGE_RELEASE", "MADEIRA_GDI_SHARED_SECTION",
                            "MADEIRA_DOCK_INSTALLS_SESSION", "MADEIRA_MADSYNC_SESSION"]

    static func prepare(appID: Int, arguments: String, width: Int, height: Int) async throws -> Prepared {
        let installed = MadeiraDock.games(drive: MadeiraDock.drive)
        guard let game = installed.first(where: { $0.id == appID && $0.installed }) else {
            throw DockError.message("This game is not installed.")
        }
        try MadeiraDock.validate(game, drive: MadeiraDock.drive)
        guard SteamSignIn.isSignedIn else { throw DockError.message("Sign in to Steam first.") }

        // A game whose executable has a fixed base above 0x140000000 needs the
        // executable window widened, so the JIT pool goes above it.
        let folder = MadeiraDock.drive.appendingPathComponent(game.library + "/common/" + game.installDir)
        StikJITHelper.exeWindowAutoMB = StikJITHelper.fixedBaseWindowMB(in: folder)?.mb ?? 0

        // Valve's client signs in with this account next; ours goes offline first.
        await Steam.shared.closeConnection()
        guard JIT.shared.isOn, wine_process_is_running() == 0, wineserver_is_running() == 0 else {
            throw DockError.message("JIT went off while Steam closed. Enable JIT and try again.")
        }
        guard let signIn = SteamSignIn.credentialsForDock() else { throw DockError.message("Sign in to Steam first.") }
        try MadeiraDock.writeHandoff(account: signIn.accountName, token: signIn.refreshToken, appID: appID)
        // Steam's first launch entry. (Choosing another one comes with game settings.)
        MadeiraDock.configure(game, launchOption: 0, arguments: arguments)

        DockInstallers.prepare(game, drive: MadeiraDock.drive, prefix: MadeiraDock.prefix, others: installed)
        let installsOnly = DockInstallers.installsOnly
        if installsOnly { MadeiraDock.cleanup() }   // no host runs to take the sign-in
        LogStore.shared.log("[session] Dock app=\(appID) installers=\(DockInstallers.script == nil ? 0 : 1) installs-only=\(installsOnly ? 1 : 0)")

        return Prepared(environment: [
            "MADEIRA_EXE": "explorer.exe",
            "MADEIRA_ARGS": MadeiraDock.launchArguments(width: width, height: height,
                                                        installers: DockInstallers.script, host: !installsOnly),
            "MADEIRA_DESKTOP": "1",
            // Valve's client gives each game its identity; no fixed Steam app ID.
            "MADEIRA_DOCK_SESSION": "1",
            // No Chromium runs here, so Wine may use the address space held for it.
            "MADEIRA_CAGE_RELEASE": "1",
            // 32-bit programs (installers, games) need the GDI handle table where
            // they can map it; a Dock session starts 64-bit.
            "MADEIRA_GDI_SHARED_SECTION": "1",
            "MADEIRA_DOCK_INSTALLS_SESSION": installsOnly ? "1" : nil,
            // A session that runs installers turns the server's madsync off.
            "MADEIRA_MADSYNC_SESSION": DockInstallers.serverSync ? "0" : nil,
        ], installsOnly: installsOnly, installs: DockInstallers.script != nil, gameFolder: game.windowsInstallPath)
    }

    /// After a Dock session (or a start that failed): an unused sign-in transfer goes.
    static func finish() {
        MadeiraDock.cleanup()
    }
}
