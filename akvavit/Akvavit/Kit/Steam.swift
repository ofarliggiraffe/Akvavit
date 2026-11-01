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

public struct SteamDownload: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case waiting, preparing, checking, downloading, finishing, failed(String) }
    public var phase: Phase
    /// 0...1 of the bytes to download.
    public var fraction: Double
    public var doneBytes: UInt64
    public var totalBytes: UInt64
    public var bytesPerSecond: Double
    /// Steam's shared redistributables (Visual C++, DirectX), which come
    /// before the game; usually only checked.
    public var sharedFiles = false
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
    @ObservationIgnored private var downloadTasks: [Int: Task<Void, Never>] = [:]
    /// Downloads in order: the first one runs, the others wait.
    @ObservationIgnored private var queue: [Int] = []
    /// Each started download's folder under `common`, for cleaning up after a cancel.
    @ObservationIgnored private var installDirs: [Int: String] = [:]

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

    private func refreshInstalled() {
        let installed = installedIDs()
        for index in games.indices { games[index].installed = installed.contains(games[index].id) }
        Games.shared.reloadInstalled()
    }

    // MARK: Uninstall

    public enum UninstallError: LocalizedError {
        case windowsRan
        case notInstalled

        public var errorDescription: String? {
            switch self {
            case .windowsRan: "Windows has run since Akvavit started and may still use the game's files. Close Akvavit, open it again, then uninstall."
            case .notInstalled: "The game isn't installed."
            }
        }
    }

    /// Deletes an installed game: its folder and its install records. A
    /// download of it stops first. Not after a session has run in this app
    /// run: Wine's processes may still hold the files.
    public func uninstall(_ appID: Int) async throws {
        guard !Session.shared.needsRestart else { throw UninstallError.windowsRan }
        if let task = downloadTasks[appID] {
            task.cancel()
            await task.value
        }
        let drive = MadeiraDock.drive
        guard let game = MadeiraDock.games(drive: drive).first(where: { $0.id == appID }) else {
            throw UninstallError.notInstalled
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
        downloads[appID] = nil
        refreshInstalled()
    }

    // MARK: Downloads

    /// Downloads that run, wait, or failed, by app ID.
    public private(set) var downloads: [Int: SteamDownload] = [:]

    /// Downloads a game (or brings it up to date), with the shared
    /// redistributables it takes from Steam. One at a time; others wait.
    /// Called from a tap: the download may go on in the background, with
    /// iOS showing its progress (DownloadActivity).
    public func install(_ appID: Int) {
        guard downloadTasks[appID] == nil else { return }
        downloads[appID] = SteamDownload(phase: .waiting, fraction: 0, doneBytes: 0, totalBytes: 0, bytesPerSecond: 0)
        queue.append(appID)
        DownloadActivity.shared.begin(title: "Downloading " + gameName(appID))
        downloadTasks[appID] = Task { [weak self] in
            // Waiting ends with its turn, or at once when cancelled.
            while let self, self.queue.first != appID, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            await self?.runInstall(appID)
        }
    }

    /// Stops a download. What is downloaded stays; installing again resumes.
    public func cancelDownload(_ appID: Int) {
        downloadTasks[appID]?.cancel()
    }

    /// A download runs or waits.
    var hasQueuedDownloads: Bool { !queue.isEmpty }

    /// Stops every download (iOS ended the background work). Files stay.
    func stopAllDownloads() {
        for task in downloadTasks.values { task.cancel() }
    }

    /// Stops a download of a game that isn't installed and deletes what it
    /// downloaded so far. A failed download's files go the same way.
    public func cancelInstall(_ appID: Int) async throws {
        if let task = downloadTasks[appID] {
            task.cancel()
            await task.value
        }
        downloads[appID] = nil
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

    private func gameName(_ appID: Int) -> String {
        Games.shared.game("steam:\(appID)")?.name ?? games.first { $0.id == appID }?.name ?? "a game"
    }

    /// Tells iOS's progress display about the first download in line.
    private func reportActivity(lastSucceeded: Bool = true) {
        guard let appID = queue.first(where: { downloads[$0] != nil }), let download = downloads[appID] else {
            DownloadActivity.shared.end(success: lastSucceeded)
            return
        }
        // Words that change only with the step: each change is an update of
        // the Live Activity. The progress carries the percentage.
        let waiting = queue.count - 1
        var subtitle: String
        if download.sharedFiles {
            subtitle = "Steam's shared files"
        } else {
            switch download.phase {
            case .downloading: subtitle = "Downloading"
            case .finishing: subtitle = "Finishing"
            case .checking: subtitle = "Checking files"
            default: subtitle = "Preparing"
            }
        }
        if waiting > 0 { subtitle += " · \(waiting) more waiting" }
        let gameProgress = !download.sharedFiles && (download.phase == .downloading || download.phase == .finishing)
        DownloadActivity.shared.update(job: appID, title: "Downloading " + gameName(appID), subtitle: subtitle,
                                       fraction: gameProgress ? download.fraction : 0)
    }

    private func runInstall(_ appID: Int) async {
        var succeeded = false
        defer {
            downloadTasks[appID] = nil
            queue.removeAll { $0 == appID }
            reportActivity(lastSucceeded: succeeded)
            // A stopped download leaves files: the list marks the game.
            if !succeeded { Games.shared.reloadInstalled() }
        }
        guard !Task.isCancelled else { downloads[appID] = nil; return }
        let library = SteamInstallPaths.libraryRelative
        do {
            try await session.ensureConnected()
            guard let info = try await fetcher.fetchInstallInfo(appID: UInt32(appID)) else {
                throw SteamError.appInfoNotFound(UInt32(appID))
            }
            installDirs[appID] = info.installDir
            let steamApps = MadeiraDock.drive.appendingPathComponent(library, isDirectory: true)
            try FileManager.default.createDirectory(at: steamApps.appendingPathComponent("common"),
                                                    withIntermediateDirectories: true)
            SteamLog.event("[akvavit-steam] install app=\(appID)")
            func report(sharedFiles: Bool) -> (SteamDownloadProgress) -> Void {
                { [weak self] progress in
                    Task { @MainActor in
                        // A report can arrive after the download ended; it must not bring it back.
                        guard let self, self.downloadTasks[appID] != nil, self.downloads[appID] != nil else { return }
                        var download = Self.download(progress)
                        download.sharedFiles = sharedFiles
                        self.downloads[appID] = download
                        self.reportActivity()
                    }
                }
            }
            try await AkvavitSteamRedist.install(for: info, library: library, fetcher: fetcher,
                                                 downloader: downloader, progress: report(sharedFiles: true))
            _ = try await downloader.install(info, steamApps: steamApps,
                                             ownedDepots: { [weak self] in try? await self?.fetcher.ownedDepotIDs() },
                                             progress: report(sharedFiles: false))
            downloads[appID] = nil
            installDirs[appID] = nil
            succeeded = true
            refreshInstalled()
            SteamLog.event("[akvavit-steam] installed app=\(appID)")
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                downloads[appID] = nil
                SteamLog.event("[akvavit-steam] stopped app=\(appID)")
            } else {
                var failed = downloads[appID] ?? SteamDownload(phase: .waiting, fraction: 0, doneBytes: 0, totalBytes: 0, bytesPerSecond: 0)
                failed.phase = .failed(SteamSignIn.message(error))
                downloads[appID] = failed
                SteamLog.event("[akvavit-steam] failed app=\(appID) reason=\(SteamSignIn.reason(error))")
            }
        }
    }

    private static func download(_ p: SteamDownloadProgress) -> SteamDownload {
        let phase: SteamDownload.Phase
        switch p.phase {
        case .preparing: phase = .preparing
        case .checking: phase = .checking
        case .downloading: phase = .downloading
        case .finishing: phase = .finishing
        }
        return SteamDownload(phase: phase, fraction: p.fraction, doneBytes: p.doneBytes,
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
    /// and only one sign-in of an account may be online. Downloads stop.
    func closeConnection() async {
        for task in downloadTasks.values { task.cancel() }
        await session.suspend()
    }
}
