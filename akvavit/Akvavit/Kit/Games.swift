// SPDX-License-Identifier: GPL-3.0-or-later
//
// One list of games for the interface, from every source (Steam and GOG).
//
// It works offline: installed games come from the install records in the
// prefix, and the last full list is kept on disk, so names, covers and facts
// show at once. What Steam and GOG say (owned games, release years, playtime)
// merges in when it arrives.

import Foundation
import Observation

public struct Game: Identifiable, Hashable, Sendable, Codable {
    public enum Source: String, Sendable, Codable {
        case steam, gog

        /// The store's name, as people know it.
        public var displayName: String {
            switch self {
            case .steam: "Steam"
            case .gog: "GOG"
            }
        }
    }

    /// "steam:<app ID>" or "gog:<product ID>".
    public let id: String
    public let source: Source
    /// The store's ID: Steam's app ID or GOG's product ID.
    public let appID: Int
    public internal(set) var name: String
    public internal(set) var installed: Bool
    /// Bytes on disk, from the install record (installed games).
    public internal(set) var sizeOnDisk: Int64?
    /// About how much a download is (Windows depots).
    public internal(set) var downloadSize: Int64?
    /// About how much room it takes once installed (Windows depots).
    public internal(set) var installSize: Int64?
    public internal(set) var releaseYear: Int?
    /// The account's playtime in minutes.
    public internal(set) var playtimeMinutes: Int?
    /// Owned and has Windows content to install.
    public internal(set) var installable: Bool
    /// Its folder under the library's `common`.
    var installDir: String?
    /// Files of a download that stopped (Install resumes it), stored as
    /// optional so lists cached before it existed still load.
    var partial: Bool?
    /// Not installed, but a stopped download left files (Install resumes it).
    public var partiallyDownloaded: Bool { !installed && partial == true }
    /// Artwork file names from the product info (relative to the app's folder
    /// on Steam's CDN).
    var capsuleImage: String?
    var headerImage: String?
    /// GOG's vertical cover, an address with `{formatter}` and `{ext}` in it.
    var gogCover: String?
    /// GOG's newest build, and the installed one (installed GOG games).
    var gogLatestBuild: String?
    var gogInstalledBuild: String?
    /// GOG has a newer version of this installed game.
    public var updateAvailable: Bool {
        installed && gogLatestBuild != nil && gogInstalledBuild != nil && gogLatestBuild != gogInstalledBuild
    }

    init(steamAppID: Int, name: String) {
        id = "steam:\(steamAppID)"
        source = .steam
        appID = steamAppID
        self.name = name
        installed = false
        installable = false
    }

    init(gogProductID: Int, name: String) {
        id = "gog:\(gogProductID)"
        source = .gog
        appID = gogProductID
        self.name = name
        installed = false
        installable = false
    }

    /// Where its cover can be found, best first.
    public var coverURLs: [URL] {
        if source == .gog {
            guard let gogCover else { return [] }
            return ["_glx_vertical_cover", ""].compactMap { formatter in
                URL(string: gogCover.replacingOccurrences(of: "{formatter}", with: formatter)
                    .replacingOccurrences(of: "{ext}", with: "jpg"))
            }
        }
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

    /// Steam apps that are installed but aren't games: Steamworks Common
    /// Redistributables (Visual C++, DirectX), which downloads install for
    /// the games that use them (AkvavitSteamRedist).
    private static let notGames: Set<Int> = [228980]

    private func sorted(_ games: some Sequence<Game>) -> [Game] {
        games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Installed games (offline)

    /// Reads the install records again: what is installed, and its size.
    public func reloadInstalled() {
        let drive = MadeiraDock.drive
        let installed = MadeiraDock.games(drive: drive).filter { $0.installed && !Self.notGames.contains($0.id) }
        for id in Self.notGames { byID["steam:\(id)"] = nil }
        let installedIDs = Set(installed.map { "steam:\($0.id)" })
        for id in byID.keys where byID[id]!.source == .steam && byID[id]!.installed && !installedIDs.contains(id) {
            byID[id]!.installed = false
            byID[id]!.sizeOnDisk = nil
        }
        for record in installed {
            var game = byID["steam:\(record.id)"] ?? Game(steamAppID: record.id, name: record.name)
            game.installed = true
            game.partial = nil
            game.sizeOnDisk = SteamInstallFiles.sizeOnDisk(
                appID: record.id, steamApps: drive.appendingPathComponent(record.library, isDirectory: true))
            byID[game.id] = game
        }
        // Folders of downloads that stopped. A folder an installed game uses isn't one.
        let common = drive.appendingPathComponent(SteamInstallPaths.libraryRelative, isDirectory: true)
            .appendingPathComponent("common", isDirectory: true)
        let installedFolders = Set(installed.map { $0.installDir.lowercased() })
        for id in byID.keys where byID[id]!.source == .steam && !byID[id]!.installed {
            guard let folder = byID[id]!.installDir, !folder.isEmpty,
                  !installedFolders.contains(folder.lowercased()) else {
                byID[id]!.partial = nil
                continue
            }
            byID[id]!.partial = FileManager.default.fileExists(atPath: common.appendingPathComponent(folder).path)
        }
        reloadInstalledGOG()
        save()
    }

    /// GOG's install records: what is installed, and stopped downloads.
    private func reloadInstalledGOG() {
        let records = GOGInstalls.installed()
        let installedIDs = Set(records.map { "gog:\($0.productID)" })
        for id in byID.keys where byID[id]!.source == .gog && byID[id]!.installed && !installedIDs.contains(id) {
            byID[id]!.installed = false
            byID[id]!.sizeOnDisk = nil
        }
        for record in records {
            var game = byID["gog:\(record.productID)"] ?? Game(gogProductID: record.productID, name: record.name)
            game.installed = true
            game.partial = nil
            game.sizeOnDisk = record.size
            game.gogInstalledBuild = record.buildID
            byID[game.id] = game
        }
        for id in byID.keys where byID[id]!.source == .gog && !byID[id]!.installed {
            byID[id]!.partial = GOGInstalls.hasJournal(byID[id]!.appID)
        }
    }

    // MARK: From Steam and GOG

    /// Asks Steam and GOG (where signed in) for the account's games and their
    /// facts. Without a connection the list stays as it was.
    public func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if SteamSignIn.isSignedIn { await refreshSteam() }
        if GOGAccount.shared.isSignedIn { await refreshGOG() }
    }

    /// Steam's games, then their release years and the playtime.
    private func refreshSteam() async {
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
            func bytes(_ size: UInt64) -> Int64? { size > 0 && size < UInt64(Int64.max) ? Int64(size) : nil }
            game.downloadSize = bytes(app.downloadSize(for: "windows"))
            game.installSize = bytes(app.installSize(for: "windows"))
            game.capsuleImage = app.libraryCapsule
            game.headerImage = app.headerImage
            game.installDir = app.installDir.isEmpty ? nil : app.installDir
            byID[game.id] = game
        }
        reloadInstalled()
    }

    // MARK: From GOG

    /// GOG's games, then the covers, years and sizes of those still without.
    private func refreshGOG() async {
        do {
            let products = try await GOGCatalog.products(try await GOGCatalog.ownedIDs())
            mergeOwnedGOG(products.filter(\.installableOnWindows))
            save()
        } catch {
            LogStore.shared.log("[gog] owned list failed: \(GOGAccount.words(error))", level: .error)
            return
        }
        // Installed games: whether GOG has a newer build.
        for game in byID.values where game.source == .gog && game.installed {
            if let build = try? await GOGCatalog.builds(game.appID).first {
                byID[game.id]?.gogLatestBuild = build.build_id
            }
        }
        // These don't change (sizes only with an update): ask for missing ones, a few at a time.
        let missing = byID.values.filter { $0.source == .gog && ($0.gogCover == nil || $0.downloadSize == nil) }.map(\.appID)
        await withTaskGroup(of: (Int, GOGGameFacts?, (download: Int64, install: Int64)?).self) { group in
            var next = missing.makeIterator()
            func add() {
                guard let id = next.next() else { return }
                group.addTask {
                    async let facts = try? GOGCatalog.facts(id)
                    async let sizes = try? GOGCatalog.sizes(id)
                    return await (id, facts, sizes)
                }
            }
            for _ in 0..<4 { add() }
            for await (id, facts, sizes) in group {
                if let facts {
                    byID["gog:\(id)"]?.gogCover = facts.coverFormat
                    if let year = facts.releaseYear { byID["gog:\(id)"]?.releaseYear = year }
                }
                if let sizes {
                    byID["gog:\(id)"]?.downloadSize = sizes.download
                    byID["gog:\(id)"]?.installSize = sizes.install
                }
                add()
            }
        }
        save()
    }

    private func mergeOwnedGOG(_ owned: [GOGProduct]) {
        let ownedIDs = Set(owned.map { "gog:\($0.id)" })
        for id in byID.keys where byID[id]!.source == .gog && !ownedIDs.contains(id) {
            if byID[id]!.installed { byID[id]!.installable = false } else { byID[id] = nil }
        }
        for product in owned {
            var game = byID["gog:\(product.id)"] ?? Game(gogProductID: product.id, name: product.title)
            game.name = product.title
            game.installable = true
            if game.releaseYear == nil { game.releaseYear = GOGCatalog.year(product.release_date) }
            byID[game.id] = game
        }
    }

    /// Signed out of GOG: only installed GOG games stay.
    func forgetGOG() {
        byID = byID.filter { $0.value.source != .gog || $0.value.installed }
        for id in byID.keys where byID[id]!.source == .gog { byID[id]!.installable = false }
        save()
    }

    /// Signed out of Steam: only installed Steam games stay, which still play through Dock.
    public func forgetAccount() {
        byID = byID.filter { $0.value.source != .steam || $0.value.installed }
        for id in byID.keys where byID[id]!.source == .steam {
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
