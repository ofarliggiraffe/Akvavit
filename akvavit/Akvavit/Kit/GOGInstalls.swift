// SPDX-License-Identifier: GPL-3.0-or-later
//
// GOG games on disk. They install into the prefix, at
// drive_c/GOG Games/<install folder> (GOG's own place for them). Our records
// sit beside them in drive_c/GOG Games/.akvavit, so a new prefix forgets them
// together with the games:
//
//   <id>.json          an installed game: name, build, folder
//   <id>.files.json    its files with their chunks (for checks and updates)
//   <id>.partial.json  a download under way or stopped: the files done so far

import Foundation

enum GOGInstalls {
    static var root: URL { MadeiraDock.drive.appendingPathComponent("GOG Games", isDirectory: true) }
    private static var records: URL { root.appendingPathComponent(".akvavit", isDirectory: true) }

    /// An installed game.
    struct Record: Codable {
        var productID: Int
        var name: String
        var buildID: String
        var version: String?
        /// Its folder under `root`.
        var folder: String
        /// Bytes of its files.
        var size: Int64
        /// GOG's dependency IDs the build lists (Visual C++, OpenAL…).
        var dependencies: [String]
    }

    /// One file of an installed game.
    struct File: Codable {
        /// Relative to the game's folder, with `/`.
        var path: String
        var size: Int64
        /// Each chunk's md5, in order.
        var chunks: [String]
    }

    /// A download that hasn't finished.
    struct Journal: Codable {
        var buildID: String
        var folder: String
        /// Files written and checked.
        var done: Set<String>
    }

    static func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    // MARK: Records

    static func installed() -> [Record] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: records.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") && !$0.contains(".files.") && !$0.contains(".partial.") }
            .compactMap { read(Record.self, records.appendingPathComponent($0)) }
    }

    static func record(_ id: Int) -> Record? { read(Record.self, file(id, "json")) }

    static func journal(_ id: Int) -> Journal? { read(Journal.self, file(id, "partial.json")) }

    static func hasJournal(_ id: Int) -> Bool { FileManager.default.fileExists(atPath: file(id, "partial.json").path) }

    static func save(_ record: Record, files: [File]) throws {
        try write(files, to: file(record.productID, "files.json"))
        try write(record, to: file(record.productID, "json"))
        try? FileManager.default.removeItem(at: file(record.productID, "partial.json"))
    }

    static func save(_ journal: Journal, for id: Int) throws {
        try write(journal, to: file(id, "partial.json"))
    }

    // MARK: Deleting

    /// Deletes what a stopped or failed download left, unless the game is
    /// installed.
    static func deletePartial(_ id: Int) async throws {
        guard record(id) == nil, let journal = journal(id) else { return }
        try await delete(folder: journal.folder, files: [file(id, "partial.json")])
        LogStore.shared.log("[gog] cancelled and deleted \(id)")
    }

    static func uninstall(_ id: Int) async throws {
        guard let record = record(id) else { throw Downloads.UninstallError.notInstalled }
        LogStore.shared.log("[gog] uninstall \(id)")
        try await delete(folder: record.folder,
                         files: [file(id, "json"), file(id, "files.json"), file(id, "partial.json")])
    }

    private static func delete(folder: String, files: [URL]) async throws {
        let target = Self.folder(folder)
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            // Only a folder inside GOG Games, never GOG Games itself.
            guard !folder.isEmpty, target.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            for file in files where manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
        }.value
    }

    // MARK: Disk

    private static func file(_ id: Int, _ suffix: String) -> URL {
        records.appendingPathComponent("\(id).\(suffix)")
    }

    private static func read<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
