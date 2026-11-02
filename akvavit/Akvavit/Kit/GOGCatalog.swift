// SPDX-License-Identifier: GPL-3.0-or-later
//
// GOG: what the account owns and what GOG says about each game. Unofficial
// endpoints, as Galaxy uses them (checked 2026-11-02):
//
//   embed.gog.com/user/data/games                  owned product IDs (signed in)
//   api.gog.com/products?ids=…                     title, kind, Windows, release date
//   gamesdb.gog.com/platforms/gog/external_releases/<id>
//                                                  vertical cover, first release date
//   content-system.gog.com/products/<id>/os/windows/builds?generation=2
//                                                  builds, newest first, each with
//                                                  its manifest's address
//
// Manifests on GOG's CDN are JSON compressed with zlib.

import Compression
import Foundation

/// A product as GOG's product list describes it.
struct GOGProduct: Decodable {
    let id: Int
    let title: String
    let game_type: String?
    let is_installable: Bool?
    let release_date: String?
    let content_system_compatibility: [String: Bool]?

    /// A game (not DLC, a pack or a film) with Windows files in GOG's content system.
    var installableOnWindows: Bool {
        game_type == "game" && is_installable != false && content_system_compatibility?["windows"] == true
    }
}

/// What gamesdb adds: the cover and the first release.
struct GOGGameFacts {
    /// The vertical cover's address with `{formatter}` and `{ext}` in it.
    var coverFormat: String?
    var releaseYear: Int?
}

enum GOGCatalog {
    // MARK: The account's games

    /// The product IDs the account owns (games, DLC, extras).
    static func ownedIDs() async throws -> [Int] {
        struct Reply: Decodable { let owned: [Int] }
        let (data, _) = try await GOGAccount.shared.authorized(URL(string: "https://embed.gog.com/user/data/games")!)
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw GOGAccount.Failure.unreadable }
        return reply.owned
    }

    /// GOG's product list for `ids`, 50 at a time (the most it takes).
    static func products(_ ids: [Int]) async throws -> [GOGProduct] {
        var products: [GOGProduct] = []
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = ids[start..<min(start + 50, ids.count)].map(String.init).joined(separator: ",")
            let url = URL(string: "https://api.gog.com/products?ids=" + batch)!
            products += try JSONDecoder().decode([GOGProduct].self, from: try await get(url))
        }
        return products
    }

    static func facts(_ id: Int) async throws -> GOGGameFacts {
        struct Reply: Decodable {
            struct Game: Decodable {
                struct Cover: Decodable { let url_format: String }
                let vertical_cover: Cover?
                let first_release_date: String?
            }
            let game: Game?
            let first_release_date: String?
        }
        let url = URL(string: "https://gamesdb.gog.com/platforms/gog/external_releases/\(id)")!
        let reply = try JSONDecoder().decode(Reply.self, from: try await get(url))
        let date = reply.game?.first_release_date ?? reply.first_release_date
        return GOGGameFacts(coverFormat: reply.game?.vertical_cover?.url_format, releaseYear: year(date))
    }

    /// The year of GOG's dates ("2008-09-16T00:00:00+0000").
    static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    // MARK: Builds

    struct Build: Decodable {
        let build_id: String
        let version_name: String?
        let generation: Int
        /// The build's manifest on GOG's CDN.
        let link: String
    }

    /// A build's manifest: what a game is made of.
    struct BuildManifest: Decodable {
        struct Depot: Decodable {
            let manifest: String
            let size: Int64
            let compressedSize: Int64
            let productId: String
            let languages: [String]
            let osBitness: [String]?
            let isGogDepot: Bool?
        }
        let baseProductId: String
        let installDirectory: String
        let depots: [Depot]
        let dependencies: [String]?
        let scriptInterpreter: Bool?
    }

    /// The Windows builds of `id` in the current format, newest first.
    static func builds(_ id: Int) async throws -> [Build] {
        struct Reply: Decodable { let items: [Build] }
        let url = URL(string: "https://content-system.gog.com/products/\(id)/os/windows/builds?generation=2")!
        return try JSONDecoder().decode(Reply.self, from: try await get(url)).items.filter { $0.generation == 2 }
    }

    static func buildManifest(_ build: Build) async throws -> BuildManifest {
        guard let url = URL(string: build.link) else { throw GOGAccount.Failure.unreadable }
        return try JSONDecoder().decode(BuildManifest.self, from: try inflated(try await get(url)))
    }

    /// The depots a download takes: the base game's, in English or for every
    /// language, 64-bit where a game has both, and GOG's own (its `goggame` files).
    static func depots(of manifest: BuildManifest) -> [BuildManifest.Depot] {
        let base = manifest.depots.filter { $0.productId == manifest.baseProductId }
        let wanted = base.filter { $0.isGogDepot == true || $0.languages.contains("*") || $0.languages.contains("en-US") }
        let has64 = wanted.contains { $0.osBitness == ["64"] }
        return wanted.filter { depot in
            guard let bitness = depot.osBitness, !bitness.isEmpty else { return true }
            return has64 ? bitness.contains("64") : bitness.contains("32")
        }
    }

    /// A file or folder of a depot. Paths use Windows' backslashes.
    struct DepotItem: Decodable {
        struct Chunk: Decodable {
            let md5: String
            let size: Int64
            let compressedMd5: String
            let compressedSize: Int64
        }
        let type: String
        let path: String
        let chunks: [Chunk]?
    }

    /// A depot's files and folders, from its manifest.
    static func depotItems(_ manifest: String) async throws -> [DepotItem] {
        struct Reply: Decodable {
            struct Depot: Decodable { let items: [DepotItem] }
            let depot: Depot
        }
        let data = try inflated(try await get(metaURL(manifest)))
        return try JSONDecoder().decode(Reply.self, from: data).depot.items
    }

    /// A manifest's place on GOG's CDN: meta/aa/bb/<hash>.
    static func metaURL(_ hash: String) throws -> URL {
        guard hash.count > 4, hash.allSatisfy(\.isHexDigit) else { throw GOGAccount.Failure.unreadable }
        return URL(string: "https://gog-cdn-fastly.gog.com/content-system/v2/meta/" + storePath(hash))!
    }

    /// aa/bb/<hash>, how GOG files manifests and chunks.
    static func storePath(_ hash: String) -> String {
        "\(hash.prefix(2))/\(hash.dropFirst(2).prefix(2))/\(hash)"
    }

    /// About how much the newest build downloads and takes on disk.
    static func sizes(_ id: Int) async throws -> (download: Int64, install: Int64)? {
        guard let build = try await builds(id).first else { return nil }
        let depots = depots(of: try await buildManifest(build))
        return (depots.reduce(0) { $0 + $1.compressedSize }, depots.reduce(0) { $0 + $1.size })
    }

    // MARK: Requests

    static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw GOGAccount.Failure.refused(status) }
        return data
    }

    /// zlib data (RFC 1950) inflated: the deflate stream between the 2-byte
    /// header and the 4-byte checksum, through Apple's Compression.
    static func inflated(_ data: Data, expectedSize: Int? = nil) throws -> Data {
        guard data.count > 6, data[data.startIndex] & 0x0F == 8 else { throw GOGAccount.Failure.unreadable }
        let deflate = data.subdata(in: data.startIndex + 2 ..< data.endIndex - 4)
        var output = Data()
        let filter = try OutputFilter(.decompress, using: .zlib) { output.append($0 ?? Data()) }
        try filter.write(deflate)
        try filter.finalize()
        if let expectedSize, output.count != expectedSize { throw GOGAccount.Failure.unreadable }
        return output
    }
}
