// SPDX-License-Identifier: GPL-3.0-or-later
//
// Steam: sign-in, the account's games, downloads, and Valve's client files
// that Madeira Dock runs. SwiftSteam (Madeira's Steam library) talks to Valve;
// this is the part the interface uses.
//
// Games are downloaded into the prefix's Steam library, drive_c/Program Files
// (x86)/Steam/steamapps, where Valve's client (through Dock) finds them.

import Combine
import Foundation
import Observation
import UIKit

public struct SteamGame: Identifiable, Hashable, Sendable {
    /// Steam's app ID.
    public let id: Int
    public let name: String
    public internal(set) var installed: Bool
}

@MainActor @Observable
public final class Steam {
    public static let shared = Steam()

    // SwiftSteam's sign-in model publishes through Combine; see JIT.revision.
    private var revision = 0
    @ObservationIgnored private var watcher: AnyCancellable?

    @ObservationIgnored let session = SteamSession()
    @ObservationIgnored private lazy var fetcher = SteamLibraryFetcher(session: session)
    @ObservationIgnored private lazy var downloader = DepotDownloader(session: session)

    private init() {
        watcher = SteamSignInModel.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.revision &+= 1 }
        }
    }

    // MARK: Sign-in

    public enum SignIn: Equatable {
        case signedOut
        /// Talking to Steam.
        case busy
        /// Scan with the Steam app (Steam Guard › QR code).
        case qrCode(UIImage)
        /// Steam Guard: a code to type (from the Steam app or an email), an
        /// approval in the Steam app, or either.
        case steamGuard(needsCode: Bool, canApprove: Bool, emailHint: String?)
        case signedIn(account: String)
    }

    public var signIn: SignIn {
        _ = revision
        let model = SteamSignInModel.shared
        if let account = model.accountName { return .signedIn(account: account) }
        if let prompt = model.guardPrompt {
            let email = prompt.codeType == .email && !prompt.hint.isEmpty ? prompt.hint : nil
            return .steamGuard(needsCode: prompt.codeType != nil, canApprove: prompt.canApprove, emailHint: email)
        }
        if let image = model.qrImage { return .qrCode(image) }
        return model.signInBusy ? .busy : .signedOut
    }

    /// The last sign-in's error, in words.
    public var signInError: String? { _ = revision; return SteamSignInModel.shared.signInError }

    public func signIn(account: String, password: String) { SteamSignInModel.shared.signIn(account: account, password: password) }
    public func signInWithQRCode() { SteamSignInModel.shared.beginQR() }
    public func submitSteamGuardCode(_ code: String) { SteamSignInModel.shared.submitGuardCode(code) }
    public func cancelSignIn() { SteamSignInModel.shared.cancelSignIn() }
    public func signOut() {
        SteamSignInModel.shared.signOut()
        games = []
        Games.shared.forgetAccount()
    }

    // MARK: Games

    /// The account's games, by name (empty until `refreshGames()`).
    public private(set) var games: [SteamGame] = []
    public private(set) var loadingGames = false
    public private(set) var gamesError: String?

    public func refreshGames() async {
        guard SteamSignIn.isSignedIn, !loadingGames else { return }
        loadingGames = true
        gamesError = nil
        defer { loadingGames = false }
        do {
            try await session.ensureConnected()
            let owned = try await fetcher.fetchOwnedApps()
            let installed = installedIDs()
            games = owned
                .map { SteamGame(id: Int($0.appID), name: $0.name, installed: installed.contains(Int($0.appID))) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            gamesError = SteamSignIn.message(error)
            SteamLog.event("[akvavit-steam] games failed: \(SteamSignIn.reason(error))")
        }
    }

    /// The account's playable apps with their product info (names, artwork,
    /// depots), for the game list.
    func ownedApps() async throws -> [SteamAppInfo] {
        try await session.ensureConnected()
        return try await fetcher.fetchOwnedApps()
    }

    /// Games with an install record in the prefix's Steam library: what Dock can start.
    private func installedIDs() -> Set<Int> {
        Set(MadeiraDock.games(drive: MadeiraDock.drive).filter(\.installed).map(\.id))
    }

    /// The build an installed game's record names (Valve's client updates it
    /// when it updates the game itself).
    static func installedBuild(_ game: DockGame, steamApps: URL) -> String? {
        let file = steamApps.appendingPathComponent("appmanifest_\(game.id).acf")
        guard let data = try? Data(contentsOf: file), var parser = try? SteamKeyValues(data),
              let build = (try? parser.read())?["AppState"]?["buildid"]?.string, build != "0" else { return nil }
        return build
    }

    private func refreshInstalled() {
        let installed = installedIDs()
        for index in games.indices { games[index].installed = installed.contains(games[index].id) }
        Games.shared.reloadInstalled()
    }

    // MARK: Uninstall

    /// Deletes an installed game: its folder and its install records (Downloads
    /// stops a download of it first). Not after a session has run in this app
    /// run: Wine's processes may still hold the files.
    func uninstall(_ appID: Int) async throws {
        let drive = MadeiraDock.drive
        guard let game = MadeiraDock.games(drive: drive).first(where: { $0.id == appID }) else {
            throw Downloads.UninstallError.notInstalled
        }
        let steamApps = drive.appendingPathComponent(game.library, isDirectory: true)
        SteamLog.event("[akvavit-steam] uninstall app=\(appID)")
        try await Task.detached(priority: .userInitiated) {
            try SteamInstallFiles.delete(appID: appID, folderName: game.installDir, steamApps: steamApps)
        }.value
        // A reinstall starts with no one-time install choices left from before.
        var ledger = DockInstallLedger.load(prefix: MadeiraDock.prefix)
        ledger.runNext[String(appID)] = nil
        ledger.setUnfinished(appID, [])
        ledger.setRequest(appID, nil)
        try? ledger.save(prefix: MadeiraDock.prefix)
        refreshInstalled()
    }

    // MARK: Downloads

    /// Each started download's folder under `common`, for cleaning up after a cancel.
    @ObservationIgnored private var installDirs: [Int: String] = [:]

    /// Deletes what a stopped or failed download of a game that isn't
    /// installed left (Downloads has stopped it).
    func deletePartial(_ appID: Int) async throws {
        guard !installedIDs().contains(appID),
              let folder = installDirs[appID] ?? Games.shared.game("steam:\(appID)")?.installDir,
              !folder.isEmpty else { return }
        let steamApps = MadeiraDock.drive.appendingPathComponent(SteamInstallPaths.libraryRelative, isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            try SteamInstallFiles.delete(appID: appID, folderName: folder, steamApps: steamApps)
        }.value
        installDirs[appID] = nil
        refreshInstalled()
        SteamLog.event("[akvavit-steam] cancelled and deleted app=\(appID)")
    }

    /// Downloads a game (or brings it up to date), with the shared
    /// redistributables it takes from Steam. Downloads runs it in its turn.
    func download(_ appID: Int, report: @escaping @MainActor (GameDownload) -> Void) async throws {
        let library = SteamInstallPaths.libraryRelative
        try await session.ensureConnected()
        guard let info = try await fetcher.fetchInstallInfo(appID: UInt32(appID)) else {
            throw SteamError.appInfoNotFound(UInt32(appID))
        }
        installDirs[appID] = info.installDir
        let steamApps = MadeiraDock.drive.appendingPathComponent(library, isDirectory: true)
        try FileManager.default.createDirectory(at: steamApps.appendingPathComponent("common"),
                                                withIntermediateDirectories: true)
        SteamLog.event("[akvavit-steam] install app=\(appID)")
        func progress(sharedFiles: Bool) -> (SteamDownloadProgress) -> Void {
            { progress in
                Task { @MainActor in
                    var download = Self.download(progress)
                    download.sharedFiles = sharedFiles
                    report(download)
                }
            }
        }
        try await AkvavitSteamRedist.install(for: info, library: library, fetcher: fetcher,
                                             downloader: downloader, progress: progress(sharedFiles: true))
        _ = try await downloader.install(info, steamApps: steamApps,
                                         ownedDepots: { [weak self] in try? await self?.fetcher.ownedDepotIDs() },
                                         progress: progress(sharedFiles: false))
        installDirs[appID] = nil
        refreshInstalled()
        SteamLog.event("[akvavit-steam] installed app=\(appID)")
    }

    private static func download(_ p: SteamDownloadProgress) -> GameDownload {
        let phase: GameDownload.Phase
        switch p.phase {
        case .preparing: phase = .preparing
        case .checking: phase = .checking
        case .downloading: phase = .downloading
        case .finishing: phase = .finishing
        }
        // While checking, how much of the files on disk has been read.
        let fraction = p.phase == .checking && p.checkTotal > 0
            ? min(1, Double(p.checkDone) / Double(p.checkTotal)) : p.fraction
        return GameDownload(phase: phase, fraction: fraction, doneBytes: p.doneBytes,
                            totalBytes: p.totalBytes, bytesPerSecond: p.bytesPerSecond)
    }

    // MARK: Valve's client, for Dock

    /// Valve's client files are in the prefix: Dock can start Steam games.
    public var clientReady: Bool { _ = revision; return MadeiraDock.clientInstalled }
    public private(set) var clientProgress: String?

    /// Downloads Valve's client files (SHA-256 checked) into the prefix.
    public func prepareClient() async throws {
        clientProgress = "Starting…"
        defer { clientProgress = nil; revision &+= 1 }
        try await SteamRuntimeInstaller.shared.prepare(prefix: MadeiraDock.prefix) { text in
            await MainActor.run { Steam.shared.clientProgress = text }
        }
    }

    // MARK: Sessions

    /// Before a game starts: Valve's own client signs in with this account,
    /// and only one sign-in of an account may be online. Downloads stop
    /// (every store's: they would slow the game down).
    func closeConnection() async {
        Downloads.shared.stopAll()
        await session.suspend()
    }
}
