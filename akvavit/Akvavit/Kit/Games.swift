// SPDX-License-Identifier: GPL-3.0-or-later
//
// One list of games for the interface, from every source (Steam for now).
//
// It works offline: installed games come from the install records in the
// prefix, and the last full list is kept on disk, so names, covers and facts
// show at once. What Steam says (owned games, release years, playtime) merges
// in when it arrives.

import Foundation
import Observation

public struct Game: Identifiable, Hashable, Sendable, Codable {
    public enum Source: String, Sendable, Codable { case steam }

    /// "steam:<app ID>".
    public let id: String
    public let source: Source
    /// Steam's app ID.
    public let appID: Int
    public internal(set) var name: String
    public internal(set) var installed: Bool
    /// Bytes on disk, from the install record (installed games).
    public internal(set) var sizeOnDisk: Int64?
    /// About how much a download is (Windows depots).
    public internal(set) var downloadSize: Int64?
    public internal(set) var releaseYear: Int?
    /// The account's playtime in minutes.
    public internal(set) var playtimeMinutes: Int?
    /// Owned and has Windows content to install.
    public internal(set) var installable: Bool
    /// Artwork file names from the product info (relative to the app's folder
    /// on Steam's CDN).
    var capsuleImage: String?
    var headerImage: String?

    init(steamAppID: Int, name: String) {
        id = "steam:\(steamAppID)"
        source = .steam
        appID = steamAppID
        self.name = name
        installed = false
        installable = false
    }

    /// Where its cover can be found, best first.
    public var coverURLs: [URL] {
        let base = "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(appID)/"
        var names: [String] = []
        if let capsuleImage { names.append(capsuleImage) }
        names += ["library_600x900_2x.jpg", "library_600x900.jpg"]
        names.append(headerImage ?? "header.jpg")
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.compactMap { URL(string: base + $0) }
    }
}

@MainActor @Observable
public final class Games {
    public static let shared = Games()

    private var byID: [String: Game] = [:]
    public private(set) var refreshing = false

    /// Installed games, by name.
    public var library: [Game] { sorted(byID.values.filter(\.installed)) }
    /// Owned games that can be installed and aren't, by name.
    public var available: [Game] { sorted(byID.values.filter { !$0.installed && $0.installable }) }

    public func game(_ id: String) -> Game? { byID[id] }

    private init() {
        load()
        reloadInstalled()
    }

    private func sorted(_ games: some Sequence<Game>) -> [Game] {
        games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Installed games (offline)

    /// Reads the install records again: what is installed, and its size.
    public func reloadInstalled() {
        let drive = MadeiraDock.drive
        let installed = MadeiraDock.games(drive: drive).filter(\.installed)
        let installedIDs = Set(installed.map { "steam:\($0.id)" })
        for id in byID.keys where byID[id]!.installed && !installedIDs.contains(id) {
            byID[id]!.installed = false
            byID[id]!.sizeOnDisk = nil
        }
        for record in installed {
            var game = byID["steam:\(record.id)"] ?? Game(steamAppID: record.id, name: record.name)
            game.installed = true
            game.sizeOnDisk = SteamInstallFiles.sizeOnDisk(
                appID: record.id, steamApps: drive.appendingPathComponent(record.library, isDirectory: true))
            byID[game.id] = game
        }
        save()
    }

    // MARK: From Steam

    /// Asks Steam for the account's games, then their release years and the
    /// playtime. Without a connection the list stays as it was.
    public func refresh() async {
        guard SteamSignIn.isSignedIn, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let steam = Steam.shared
        do {
            let owned = try await steam.ownedApps()
            mergeOwned(owned)
            save()
        } catch {
            SteamLog.event("[akvavit-games] owned list failed: \(SteamSignIn.reason(error))")
            return
        }
        // Release years don't change; ask only for games without one.
        let missingYears = byID.values.filter { $0.source == .steam && $0.releaseYear == nil }.map(\.appID)
        do {
            let years = try await steam.releaseYears(missingYears.sorted())
            for (appID, year) in years { byID["steam:\(appID)"]?.releaseYear = year }
            save()
        } catch {
            SteamLog.event("[akvavit-games] release years failed: \(SteamSignIn.reason(error))")
        }
        do {
            let minutes = try await steam.playtimes()
            for id in byID.keys where byID[id]!.source == .steam {
                byID[id]!.playtimeMinutes = minutes[byID[id]!.appID]
            }
            save()
        } catch {
            SteamLog.event("[akvavit-games] playtime failed: \(SteamSignIn.reason(error))")
        }
    }

    private func mergeOwned(_ owned: [SteamAppInfo]) {
        let ownedIDs = Set(owned.map { "steam:\($0.appID)" })
        // Games no longer owned stay only while installed.
        for id in byID.keys where byID[id]!.source == .steam && !ownedIDs.contains(id) {
            if byID[id]!.installed { byID[id]!.installable = false } else { byID[id] = nil }
        }
        for app in owned {
            var game = byID["steam:\(app.appID)"] ?? Game(steamAppID: Int(app.appID), name: app.name)
            if !app.name.isEmpty { game.name = app.name }
            game.installable = app.installableOnWindows
            let size = app.downloadSize(for: "windows")
            game.downloadSize = size > 0 && size < UInt64(Int64.max) ? Int64(size) : nil
            game.capsuleImage = app.libraryCapsule
            game.headerImage = app.headerImage
            byID[game.id] = game
        }
    }

    /// Signed out: only installed games stay, which still play through Dock.
    public func forgetAccount() {
        byID = byID.filter { $0.value.installed }
        for id in byID.keys {
            byID[id]!.playtimeMinutes = nil
            byID[id]!.installable = false
        }
        save()
    }

    // MARK: Disk

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("akvavit-games.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let games = try? JSONDecoder().decode([Game].self, from: data) else { return }
        byID = Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    @ObservationIgnored private var saving: Task<Void, Never>?

    /// Writes the list atomically, off the main thread, one write after another.
    private func save() {
        let games = Array(byID.values)
        let url = Self.fileURL
        let previous = saving
        saving = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(games) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
