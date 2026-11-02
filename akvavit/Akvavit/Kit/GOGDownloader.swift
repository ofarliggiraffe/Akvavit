// SPDX-License-Identifier: GPL-3.0-or-later
//
// Downloads a GOG game from GOG's content system (generation 2), the way
// Galaxy gets its files:
//
//   1. the newest Windows build and its manifest (GOGCatalog);
//   2. the depots for this download (base game, English or every language,
//      64-bit where there is a choice, GOG's own files);
//   3. each depot's files, each in chunks: zlib data on GOG's CDN, named by
//      the md5 of the compressed bytes, reached through a signed link per
//      product that expires (`secure_link`, signed in). Every chunk is
//      checked twice (compressed and plain md5) and written into its file at
//      its offset; a few download at once.
//
// A stopped download keeps a journal of the files it finished; installing
// again does the rest. Newer builds also pack small files into one container
// (`sfcRef`); every file still has its own chunks, which is what this uses.

import CryptoKit
import Foundation

struct GOGDownloader {
    let productID: Int
    let name: String

    enum Failure: LocalizedError {
        case noBuild
        case notEnoughSpace(Int64)
        case damaged
        case badPath(String)

        var errorDescription: String? {
            switch self {
            case .noBuild: "GOG has no Windows version of this game for Galaxy."
            case .notEnoughSpace(let bytes):
                "Not enough space: it needs \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) more."
            case .damaged: "Some of the game's files came damaged several times. Try again later."
            case .badPath(let path): "GOG's file list has a path Akvavit won't write: \(path)"
            }
        }
    }

    /// Chunks downloading at once.
    private static let parallel = 4

    func install(report: @escaping @MainActor (GameDownload) -> Void) async throws {
        await report(GameDownload(phase: .preparing, fraction: 0, doneBytes: 0, totalBytes: 0, bytesPerSecond: 0))
        guard let build = try await GOGCatalog.builds(productID).first else { throw Failure.noBuild }
        let manifest = try await GOGCatalog.buildManifest(build)
        if let record = GOGInstalls.record(productID), record.buildID == build.build_id { return }
        LogStore.shared.log("[gog] install \(productID) build=\(build.build_id) \(build.version_name ?? "")"
                            + (manifest.scriptInterpreter == true ? " (has an install script, not run)" : ""))

        // The files, from every depot of this download.
        var files: [PlannedFile] = []
        var folders: [String] = []
        for depot in GOGCatalog.depots(of: manifest) {
            for item in try await GOGCatalog.depotItems(depot.manifest) {
                let path = try Self.safePath(item.path)
                if item.type == "DepotDirectory" {
                    folders.append(path)
                } else if item.type == "DepotFile" {
                    files.append(PlannedFile(path: path, product: depot.productId, chunks: item.chunks ?? []))
                }
            }
        }
        // A later depot's file wins (GOG lists language files after the shared ones).
        var seen = Set<String>()
        files = Array(files.reversed().filter { seen.insert($0.path.lowercased()).inserted }.reversed())

        let folderName = manifest.installDirectory
        _ = try Self.safePath(folderName)
        let gameFolder = GOGInstalls.folder(folderName)
        var journal = GOGInstalls.journal(productID)
        if journal?.buildID != build.build_id || journal?.folder != folderName {
            journal = GOGInstalls.Journal(buildID: build.build_id, folder: folderName, done: [])
        }
        var done = journal!.done
        let toDo = files.filter { !done.contains($0.path) }

        // Room for what is left.
        let needed = toDo.reduce(Int64(0)) { $0 + $1.size }
        let free = (try? GOGInstalls.root.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? Int64.max
        if needed > free { throw Failure.notEnoughSpace(needed - free) }

        // Folders and empty files first: chunks are written into them.
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        try GOGInstalls.save(journal!, for: productID)
        try await Task.detached(priority: .utility) {
            let manager = FileManager.default
            for folder in folders {
                try manager.createDirectory(at: gameFolder.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            for file in toDo {
                let url = gameFolder.appendingPathComponent(file.path)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard manager.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            }
        }.value
        for file in toDo where file.chunks.isEmpty { done.insert(file.path) }

        // The chunks.
        let total = files.reduce(Int64(0)) { $0 + $1.downloadSize }
        var downloaded = files.filter { done.contains($0.path) }.reduce(Int64(0)) { $0 + $1.downloadSize }
        var left: [String: Int] = [:]
        var jobs: [Job] = []
        for file in toDo where !file.chunks.isEmpty {
            left[file.path] = file.chunks.count
            var offset: Int64 = 0
            for chunk in file.chunks {
                jobs.append(Job(file: gameFolder.appendingPathComponent(file.path), path: file.path,
                                product: file.product, chunk: chunk, offset: offset))
                offset += chunk.size
            }
        }
        let links = ChunkLinks()
        var meter = Meter(done: downloaded)
        var lastSaved = Date()
        defer {
            // Stopped or failed: keep what is done for the next try.
            if done.count < files.count {
                journal!.done = done
                try? GOGInstalls.save(journal!, for: productID)
            }
        }
        await report(meter.report(downloaded, total, phase: .downloading, force: true)!)
        try await withThrowingTaskGroup(of: Job.self) { group in
            var next = jobs.makeIterator()
            for _ in 0..<Self.parallel {
                guard let job = next.next() else { break }
                group.addTask { try await Self.fetch(job, links: links) }
            }
            for try await job in group {
                downloaded += job.chunk.compressedSize
                left[job.path]! -= 1
                if left[job.path] == 0 { done.insert(job.path) }
                if let job = next.next() { group.addTask { try await Self.fetch(job, links: links) } }
                if let update = meter.report(downloaded, total, phase: .downloading) { await report(update) }
                if Date().timeIntervalSince(lastSaved) > 5 {
                    journal!.done = done
                    try? GOGInstalls.save(journal!, for: productID)
                    lastSaved = Date()
                }
            }
        }

        await report(meter.report(downloaded, total, phase: .finishing, force: true)!)
        let record = GOGInstalls.Record(productID: productID, name: name, buildID: build.build_id,
                                        version: build.version_name, folder: folderName,
                                        size: files.reduce(0) { $0 + $1.size },
                                        dependencies: manifest.dependencies ?? [])
        try GOGInstalls.save(record, files: files.map {
            GOGInstalls.File(path: $0.path, size: $0.size, chunks: $0.chunks.map(\.md5))
        })
        LogStore.shared.log("[gog] installed \(productID): \(files.count) files, \(record.size) bytes")
    }

    // MARK: Chunks

    private struct PlannedFile {
        let path: String
        let product: String
        let chunks: [GOGCatalog.DepotItem.Chunk]
        var size: Int64 { chunks.reduce(0) { $0 + $1.size } }
        var downloadSize: Int64 { chunks.reduce(0) { $0 + $1.compressedSize } }
    }

    private struct Job: Sendable {
        let file: URL
        let path: String
        let product: String
        let chunk: GOGCatalog.DepotItem.Chunk
        let offset: Int64
    }

    /// Downloads, checks and writes one chunk; a damaged or refused one is
    /// tried again a few times (a refused link renewed first).
    private static func fetch(_ job: Job, links: ChunkLinks) async throws -> Job {
        var lastError: Error = Failure.damaged
        for attempt in 0..<4 {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: .seconds(attempt)) }
            do {
                let url = try await links.url(product: job.product, chunk: job.chunk.compressedMd5)
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 || status == 403 {
                    await links.expire(job.product)
                    lastError = GOGAccount.Failure.refused(status)
                    continue
                }
                guard status == 200 else { lastError = GOGAccount.Failure.refused(status); continue }
                guard data.count == job.chunk.compressedSize, md5(data) == job.chunk.compressedMd5,
                      let plain = try? GOGCatalog.inflated(data, expectedSize: Int(job.chunk.size)),
                      md5(plain) == job.chunk.md5 else {
                    lastError = Failure.damaged
                    continue
                }
                let handle = try FileHandle(forWritingTo: job.file)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(job.offset))
                try handle.write(contentsOf: plain)
                return job
            } catch let error as URLError where error.code != .cancelled {
                lastError = error
            }
        }
        throw lastError
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpMaximumConnectionsPerHost = parallel + 2
        return URLSession(configuration: configuration)
    }()

    private static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A depot path as a relative path with `/`; nothing that leaves the folder.
    static func safePath(_ windowsPath: String) throws -> String {
        let parts = windowsPath.split(whereSeparator: { $0 == "\\" || $0 == "/" }).map(String.init)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains("."),
              !windowsPath.hasPrefix("\\"), !windowsPath.hasPrefix("/"), !windowsPath.contains(":") else {
            throw Failure.badPath(windowsPath)
        }
        return parts.joined(separator: "/")
    }

    // MARK: Progress

    /// Turns bytes into reports, at most four a second, with a smoothed speed.
    private struct Meter {
        var lastBytes: Int64
        var lastTime = Date()
        var lastReport = Date.distantPast
        var speed: Double = 0

        init(done: Int64) { lastBytes = done }

        mutating func report(_ done: Int64, _ total: Int64, phase: GameDownload.Phase, force: Bool = false) -> GameDownload? {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= 1 {
                let current = Double(done - lastBytes) / elapsed
                speed = speed == 0 ? current : speed * 0.7 + current * 0.3
                lastBytes = done
                lastTime = now
            }
            guard force || now.timeIntervalSince(lastReport) >= 0.25 else { return nil }
            lastReport = now
            return GameDownload(phase: phase, fraction: total > 0 ? Double(done) / Double(total) : 0,
                                doneBytes: UInt64(max(done, 0)), totalBytes: UInt64(max(total, 0)), bytesPerSecond: speed)
        }
    }
}

/// The signed links to GOG's chunk store, one per product, fetched when
/// first needed and again when the CDN refuses one.
private actor ChunkLinks {
    private struct Link {
        let format: String
        let parameters: [String: String]
    }

    private var links: [String: Link] = [:]
    private var fetching: [String: Task<Link, Error>] = [:]

    func url(product: String, chunk md5: String) async throws -> URL {
        let link = try await link(product)
        var parameters = link.parameters
        // The chunk's place in the store goes after the link's own path.
        let path = (parameters["path"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parameters["path"] = "/" + path + "/" + GOGCatalog.storePath(md5)
        var text = link.format
        for (key, value) in parameters { text = text.replacingOccurrences(of: "{\(key)}", with: value) }
        guard let url = URL(string: text) else { throw GOGAccount.Failure.unreadable }
        return url
    }

    func expire(_ product: String) {
        links[product] = nil
    }

    private func link(_ product: String) async throws -> Link {
        if let link = links[product] { return link }
        if let task = fetching[product] { return try await task.value }
        let task = Task { try await Self.request(product) }
        fetching[product] = task
        defer { fetching[product] = nil }
        let link = try await task.value
        links[product] = link
        return link
    }

    private static func request(_ product: String) async throws -> Link {
        guard Int(product) != nil else { throw GOGAccount.Failure.unreadable }
        let url = URL(string: "https://content-system.gog.com/products/\(product)/secure_link?generation=2&path=/&_version=2")!
        let (data, _) = try await GOGAccount.shared.authorized(url)
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urls = reply["urls"] as? [[String: Any]], !urls.isEmpty else { throw GOGAccount.Failure.unreadable }
        // GOG lists its CDNs best first.
        let first = urls[0]
        guard let format = first["url_format"] as? String,
              let raw = first["parameters"] as? [String: Any] else { throw GOGAccount.Failure.unreadable }
        let parameters = raw.mapValues { value in
            (value as? String) ?? (value as? NSNumber)?.stringValue ?? "\(value)"
        }
        LogStore.shared.log("[gog] chunk link for \(product): \(first["endpoint_name"] as? String ?? "?") of \(urls.count)")
        return Link(format: format, parameters: parameters)
    }
}
