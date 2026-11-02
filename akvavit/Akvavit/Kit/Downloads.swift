// SPDX-License-Identifier: GPL-3.0-or-later
//
// Downloads from every store, in one queue: the first one runs, the others
// wait, whichever store they come from. Each store does its own download
// work (Steam, GOGDownloader); this keeps the queue, each download's state
// for the interface, and iOS's background task (DownloadActivity).

import Foundation
import Observation

public struct GameDownload: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case waiting, preparing, checking, downloading, finishing, failed(String) }
    public var phase: Phase
    /// 0...1 of the bytes to download.
    public var fraction: Double
    public var doneBytes: UInt64
    public var totalBytes: UInt64
    public var bytesPerSecond: Double
    /// Files other games share (Steam's redistributables), which come before
    /// the game; usually only checked.
    public var sharedFiles = false

    static let waiting = GameDownload(phase: .waiting, fraction: 0, doneBytes: 0, totalBytes: 0, bytesPerSecond: 0)
}

@MainActor @Observable
public final class Downloads {
    public static let shared = Downloads()

    /// Downloads that run, wait, or failed, by game ID ("steam:…", "gog:…").
    public private(set) var state: [String: GameDownload] = [:]

    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// Downloads in order: the first one runs, the others wait.
    @ObservationIgnored private var queue: [String] = []

    private init() {}

    public subscript(_ gameID: String) -> GameDownload? { state[gameID] }

    /// Downloads a game (or brings it up to date). One at a time; others
    /// wait. Called from a tap: the download may go on in the background,
    /// with iOS showing its progress (DownloadActivity).
    public func install(_ gameID: String) {
        guard tasks[gameID] == nil, let (source, id) = Self.parse(gameID) else { return }
        state[gameID] = .waiting
        queue.append(gameID)
        DownloadActivity.shared.begin(title: "Downloading " + name(gameID))
        tasks[gameID] = Task { [weak self] in
            // Waiting ends with its turn, or at once when cancelled.
            while let self, self.queue.first != gameID, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            await self?.run(gameID, source, id)
        }
    }

    /// Stops a download. What is downloaded stays; installing again resumes.
    public func cancelDownload(_ gameID: String) {
        tasks[gameID]?.cancel()
    }

    /// Stops a download of a game that isn't installed and deletes what it
    /// downloaded so far. A failed download's files go the same way.
    public func cancelInstall(_ gameID: String) async throws {
        await stop(gameID)
        state[gameID] = nil
        guard let (source, id) = Self.parse(gameID) else { return }
        switch source {
        case .steam: try await Steam.shared.deletePartial(id)
        case .gog: try await GOGInstalls.deletePartial(id)
        }
        Games.shared.reloadInstalled()
    }

    /// Deletes an installed game. A download of it stops first.
    public func uninstall(_ gameID: String) async throws {
        guard !Session.shared.needsRestart else { throw UninstallError.windowsRan }
        await stop(gameID)
        guard let (source, id) = Self.parse(gameID) else { return }
        switch source {
        case .steam: try await Steam.shared.uninstall(id)
        case .gog: try await GOGInstalls.uninstall(id)
        }
        state[gameID] = nil
        Games.shared.reloadInstalled()
    }

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

    /// A download runs or waits.
    var hasQueued: Bool { !queue.isEmpty }

    /// Stops every download (iOS ended the background work, or a game
    /// starts). Files stay.
    func stopAll() {
        for task in tasks.values { task.cancel() }
    }

    private func stop(_ gameID: String) async {
        guard let task = tasks[gameID] else { return }
        task.cancel()
        await task.value
    }

    private static func parse(_ gameID: String) -> (Game.Source, Int)? {
        let parts = gameID.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let source = Game.Source(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
        return (source, id)
    }

    private func name(_ gameID: String) -> String {
        Games.shared.game(gameID)?.name ?? "a game"
    }

    private func run(_ gameID: String, _ source: Game.Source, _ id: Int) async {
        var succeeded = false
        defer {
            tasks[gameID] = nil
            queue.removeAll { $0 == gameID }
            reportActivity(lastSucceeded: succeeded)
            // A stopped download leaves files: the list marks the game.
            Games.shared.reloadInstalled()
        }
        guard !Task.isCancelled else { state[gameID] = nil; return }
        // A report can arrive after the download ended; it must not bring it back.
        let report: @MainActor (GameDownload) -> Void = { [weak self] download in
            guard let self, self.tasks[gameID] != nil, self.state[gameID] != nil else { return }
            self.state[gameID] = download
            self.reportActivity()
        }
        do {
            switch source {
            case .steam: try await Steam.shared.download(id, report: report)
            case .gog: try await GOGDownloader(productID: id, name: name(gameID)).install(report: report)
            }
            state[gameID] = nil
            succeeded = true
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                state[gameID] = nil
                LogStore.shared.log("[downloads] stopped \(gameID)")
            } else {
                var failed = state[gameID] ?? .waiting
                failed.phase = .failed(Self.words(source, error))
                state[gameID] = failed
                LogStore.shared.log("[downloads] failed \(gameID): \(Self.words(source, error))", level: .error)
            }
        }
    }

    private static func words(_ source: Game.Source, _ error: Error) -> String {
        switch source {
        case .steam: SteamSignIn.message(error)
        case .gog: GOGAccount.words(error)
        }
    }

    /// Tells iOS's progress display about the first download in line.
    private func reportActivity(lastSucceeded: Bool = true) {
        guard let gameID = queue.first(where: { state[$0] != nil }), let download = state[gameID] else {
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
        DownloadActivity.shared.update(job: gameID, title: "Downloading " + name(gameID), subtitle: subtitle,
                                       fraction: gameProgress ? download.fraction : 0)
    }
}
