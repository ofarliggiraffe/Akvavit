// SPDX-License-Identifier: GPL-3.0-or-later
//
// Steam's shared redistributables, downloaded through Steam as Valve's desktop client does.
//
// Some games take depots from another app with `depotfromapp` and `sharedinstall "1"`:
// Microsoft's Visual C++ and DirectX installers in "Steamworks Common Redistributables"
// (228980). Madeira's downloader leaves sharedinstall depots out (SteamAppInfo.installDepots),
// so the owner app never got a record, and Valve's client refused the game's launch until
// it had one (error 17, dependency not ready; Age of Empires II HD and DE).
//
// Before a game's download or Repair, these depots are downloaded as the owner app's own
// install: into common/<its installdir> ("Steamworks Shared"), with its record, by the same
// DepotDownloader. The record keeps the depots earlier games brought. The game's record
// lists them under SharedDepots (DepotDownloader.install), as Valve's client writes it.
// Madeira Dock's one-time installs (DockInstallers.swift) then run the installers' scripts
// from Steamworks Shared/_CommonRedist at the game's next start. Steam serves the files to
// this device; nothing from Microsoft is bundled.
//
// Hooks in Madeira's files, marked "Akvavit:": SteamOwnedLibrary.run and
// DepotDownloader.install.

import Foundation

enum AkvavitSteamRedist {
    /// The game's Windows redistributable depots and the apps they belong to.
    static func depots(of app: SteamAppInfo) -> [(depotID: Int, ownerAppID: Int)] {
        app.depots.filter { $0.isSharedInstall && $0.dlcAppID == nil && $0.supports(os: "windows") }
            .compactMap { depot in depot.fromApp.map { (Int(depot.depotID), Int($0)) } }
            .sorted { $0.depotID < $1.depotID }
    }

    /// Downloads the game's redistributable depots as their owner apps' installs, in the
    /// game's library. Nothing happens for a game without them.
    @MainActor
    static func install(for app: SteamAppInfo, library: String, fetcher: SteamLibraryFetcher,
                        downloader: DepotDownloader,
                        progress: @escaping (SteamDownloadProgress) -> Void) async throws {
        let wanted = depots(of: app)
        guard !wanted.isEmpty else { return }
        let steamApps = try ExternalDrives.nativeURL(library, write: true)
        for owner in Set(wanted.map(\.ownerAppID)).sorted() {
            try Task.checkCancellation()
            guard var info = try await fetcher.fetchAppInfo(appID: UInt32(owner)) else {
                throw SteamError.appInfoNotFound(UInt32(owner))
            }
            let held = installed(appID: owner, steamApps: steamApps)
            let ids = Set(wanted.filter { $0.ownerAppID == owner }.map(\.depotID)).union(held)
            info.depots = info.depots.filter { ids.contains(Int($0.depotID)) }
            let folder = SteamInstallFiles.safeFolderName(info.installDir.isEmpty ? "app_\(owner)" : info.installDir)
            _ = try ExternalDrives.nativeURL(library + "/common/" + folder, write: true)
            _ = try ExternalDrives.nativeURL(library + "/downloading/\(owner)", write: true)
            SteamLog.event("[steam-redist] app=\(app.appID) owner=\(owner) depots=\(info.installDepots().map { String($0.depotID) }.joined(separator: ",")) held=\(held.count)")
            _ = try await downloader.install(info, steamApps: steamApps, progress: progress)
        }
    }

    /// The depots an app's install record holds (`InstalledDepots`).
    private static func installed(appID: Int, steamApps: URL) -> Set<Int> {
        let url = steamApps.appendingPathComponent("appmanifest_\(appID).acf")
        guard let data = try? Data(contentsOf: url), data.count <= 1 << 20,
              var parser = try? SteamKeyValues(data), let root = try? parser.read(),
              let state = root["AppState"], state["appid"]?.string == String(appID) else { return [] }
        return Set((state["InstalledDepots"]?.fields ?? [:]).keys.prefix(256).compactMap { Int($0) })
    }
}
