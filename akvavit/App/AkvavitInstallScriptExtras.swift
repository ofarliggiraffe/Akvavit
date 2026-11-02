// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rest of a game's Steam install script (installscript.vdf), beside the
// "Run Process" entries Madeira Dock runs (DockInstallers.swift):
//
//   "Registry"      keys and values Steam writes before a game's first start,
//                   e.g. Skyrim's HKLM\SOFTWARE\Bethesda Softworks\Skyrim
//                   "Installed Path", without which its launcher offers
//                   INSTALL instead of PLAY;
//   "Copy Folders"  folders Steam copies, e.g. Skyrim's default settings into
//                   Documents\My Games\Skyrim.
//
// On a PC, Steam's Windows service does both. Dock has no such service, so
// they are done here before each Dock start, while no session runs (the
// registry files are on disk then). Both are idempotent: values are written
// when they differ, files are copied only when missing.
//
// Hook in Madeira's DockInstallers.swift, marked "Akvavit:": DockInstallers.prepare.

import Foundation

enum AkvavitInstallScriptExtras {
    /// A text VDF tree with its keys' case kept (registry names are shown as written).
    indirect enum Node {
        case text(String)
        case list([(key: String, value: Node)])

        var entries: [(key: String, value: Node)] { if case .list(let entries) = self { entries } else { [] } }
        var text: String? { if case .text(let text) = self { text } else { nil } }
        func first(_ key: String) -> Node? {
            entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
        }
    }

    /// One registry value a script sets.
    struct Value: Equatable {
        var machine: Bool
        var key: String       // under the hive, e.g. SOFTWARE\Bethesda Softworks\Skyrim
        var name: String
        var data: Data        // the line's right side, e.g. "C:\\Games\\" or dword:00000001
        enum Data: Equatable { case string(String), dword(UInt32) }
    }

    @MainActor static func apply(_ game: DockGame, drive: URL, prefix: URL) {
        let folder = drive.appendingPathComponent(game.library + "/common/" + game.installDir, isDirectory: true)
        let documents = documentsFolder(prefix: prefix)
        let variables = [
            "%INSTALLDIR%": game.windowsInstallPath,
            "%ROOTDRIVE%": "C:",
            "%USER_MYDOCS%": documents ?? "",
        ]
        for script in scripts(folder: folder) {
            guard let data = try? Data(contentsOf: script), data.count <= 1 << 20,
                  let root = try? parse(data).first("InstallScript") else { continue }
            let name = script.lastPathComponent
            let values = registryValues(root, variables: variables)
            if !values.isEmpty {
                do {
                    let changed = try write(values, prefix: prefix)
                    LogStore.shared.log("[akvavit-script] app=\(game.id) \(name): registry values=\(values.count) written=\(changed)")
                } catch {
                    LogStore.shared.log("[akvavit-script] app=\(game.id) registry not written: \(error.localizedDescription)", level: .error)
                }
            }
            for (source, target) in copyFolders(root, variables: variables) {
                guard let from = unixPath(source, drive: drive), let to = unixPath(target, drive: drive) else {
                    LogStore.shared.log("[akvavit-script] app=\(game.id) copy skipped: \(source) -> \(target)")
                    continue
                }
                let copied = copyMissing(from: from, to: to)
                LogStore.shared.log("[akvavit-script] app=\(game.id) copy \(source) -> \(target): files=\(copied)")
            }
        }
    }

    // MARK: Reading

    /// The game folder's .vdf files (and one level below) with a Registry or
    /// Copy Folders section.
    static func scripts(folder: URL, depth: Int = 1) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for item in items.sorted(by: { $0.path < $1.path }).prefix(500) {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if depth > 0 { found += scripts(folder: item, depth: depth - 1) }
            } else if item.pathExtension.lowercased() == "vdf", (values.fileSize ?? .max) <= 1 << 20,
                      let data = try? Data(contentsOf: item) {
                let text = String(decoding: data, as: UTF8.self)
                if text.range(of: "\"registry\"", options: .caseInsensitive) != nil
                    || text.range(of: "\"copy folders\"", options: .caseInsensitive) != nil {
                    found.append(item)
                }
            }
        }
        return found
    }

    /// Valve's text format: quoted or bare words, braces, // comments. Keys
    /// may repeat, so each object is a list.
    static func parse(_ data: Data) throws -> Node {
        var bytes = Array(data)
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) { bytes.removeFirst(3) }
        var position = 0
        enum Token { case word(String), open, close }
        func token() throws -> Token? {
            while position < bytes.count {
                if bytes[position] <= 32 { position += 1; continue }
                if bytes[position] == 47, position + 1 < bytes.count, bytes[position + 1] == 47 {
                    while position < bytes.count, bytes[position] != 10 { position += 1 }
                    continue
                }
                break
            }
            guard position < bytes.count else { return nil }
            let first = bytes[position]
            position += 1
            if first == 123 { return .open }
            if first == 125 { return .close }
            var word: [UInt8] = []
            if first == 34 {
                while position < bytes.count {
                    let byte = bytes[position]
                    position += 1
                    if byte == 34 { return .word(String(decoding: word, as: UTF8.self)) }
                    if byte == 92, position < bytes.count, bytes[position] == 34 || bytes[position] == 92 {
                        word.append(bytes[position])
                        position += 1
                    } else {
                        word.append(byte)
                    }
                }
                throw CocoaError(.fileReadCorruptFile)
            }
            word.append(first)
            while position < bytes.count, bytes[position] > 32, bytes[position] != 123, bytes[position] != 125 {
                word.append(bytes[position])
                position += 1
            }
            return .word(String(decoding: word, as: UTF8.self))
        }
        func list(depth: Int) throws -> Node {
            guard depth < 32 else { throw CocoaError(.fileReadCorruptFile) }
            var entries: [(key: String, value: Node)] = []
            while let next = try token() {
                switch next {
                case .close:
                    guard depth > 0 else { throw CocoaError(.fileReadCorruptFile) }
                    return .list(entries)
                case .open:
                    throw CocoaError(.fileReadCorruptFile)
                case .word(let key):
                    switch try token() {
                    case .word(let text): entries.append((key, .text(text)))
                    case .open: entries.append((key, try list(depth: depth + 1)))
                    default: throw CocoaError(.fileReadCorruptFile)
                    }
                }
            }
            guard depth == 0 else { throw CocoaError(.fileReadCorruptFile) }
            return .list(entries)
        }
        return try list(depth: 0)
    }

    /// The Registry section's values. A type section holds names and values,
    /// or language sections of them (English is taken).
    static func registryValues(_ root: Node, variables: [String: String]) -> [Value] {
        var values: [Value] = []
        for (path, types) in root.first("Registry")?.entries ?? [] {
            guard let (hive, key) = SteamInstallScripts.hive(path), !key.isEmpty else { continue }
            for (type, entries) in types.entries {
                let kind = type.lowercased()
                guard kind == "string" || kind == "dword" else { continue }
                var pairs: [(String, String)] = []
                for (name, node) in entries.entries {
                    if let text = node.text {
                        pairs.append((name, text))
                    } else if name.caseInsensitiveCompare("english") == .orderedSame {
                        pairs += node.entries.compactMap { entry in entry.value.text.map { (entry.key, $0) } }
                    }
                }
                for (name, raw) in pairs {
                    guard let text = substitute(raw, variables) else { continue }
                    let data: Value.Data
                    if kind == "string" {
                        data = .string(text)
                    } else if let number = UInt32(text) ?? (text.lowercased().hasPrefix("0x") ? UInt32(text.dropFirst(2), radix: 16) : nil) {
                        data = .dword(number)
                    } else { continue }
                    values.append(Value(machine: hive == .machine, key: key, name: name, data: data))
                }
            }
        }
        return values
    }

    /// The Copy Folders section's pairs ("SrcFolder 1" with "DstFolder 1").
    static func copyFolders(_ root: Node, variables: [String: String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        for (_, entry) in root.first("Copy Folders")?.entries ?? [] {
            for (key, node) in entry.entries where key.lowercased().hasPrefix("srcfolder") {
                let number = key.dropFirst("srcfolder".count)
                guard let source = node.text.flatMap({ substitute($0, variables) }),
                      let target = entry.first("DstFolder" + number)?.text.flatMap({ substitute($0, variables) }) else { continue }
                pairs.append((source, target))
            }
        }
        return pairs
    }

    /// The text with the known variables replaced; nil when one is unknown or empty.
    static func substitute(_ text: String, _ variables: [String: String]) -> String? {
        var result = text
        for (name, value) in variables where result.range(of: name, options: .caseInsensitive) != nil {
            guard !value.isEmpty else { return nil }
            result = result.replacingOccurrences(of: name, with: value, options: .caseInsensitive)
        }
        return result.contains("%") && result.range(of: "%[A-Za-z_]+%", options: .regularExpression) != nil ? nil : result
    }

    // MARK: Writing

    /// Sets the values in system.reg and user.reg, in both registry views
    /// for HKLM\Software (as Madeira records runs). Returns how many changed.
    static func write(_ values: [Value], prefix: URL) throws -> Int {
        var total = 0
        for (machine, file) in [(true, "system.reg"), (false, "user.reg")] {
            let selected = values.filter { $0.machine == machine }
            let registry = prefix.appendingPathComponent(file)
            guard !selected.isEmpty, let contents = try? Data(contentsOf: registry), !contents.isEmpty else { continue }
            let (text, changed) = set(selected, in: String(decoding: contents, as: UTF8.self),
                                      now: Int(Date().timeIntervalSince1970))
            guard changed > 0 else { continue }
            try Data(text.utf8).write(to: registry, options: .atomic)
            total += changed
        }
        return total
    }

    /// Wine's .reg text with each value set: "[Key\\Sub] <time>" headers, then
    /// "\"name\"=..." lines.
    static func set(_ values: [Value], in text: String, now: Int) -> (text: String, changed: Int) {
        var lines = text.components(separatedBy: "\n")
        var changed = 0
        for value in values {
            let nameField = "\"" + escape(value.name) + "\"="
            let line = nameField + {
                switch value.data {
                case .string(let string): "\"" + escape(string) + "\""
                case .dword(let number): String(format: "dword:%08x", number)
                }
            }()
            var keys = [value.key]
            let lower = value.key.lowercased()
            if value.machine, lower.hasPrefix("software\\"), !lower.hasPrefix("software\\wow6432node\\") {
                keys.append("Software\\Wow6432Node\\" + value.key.dropFirst("software\\".count))
            }
            for key in keys {
                let header = "[" + escape(key) + "]"
                if let start = lines.firstIndex(where: { $0.lowercased().hasPrefix(header.lowercased()) }) {
                    var end = start + 1
                    while end < lines.count, !lines[end].hasPrefix("[") { end += 1 }
                    if let index = (start + 1..<end).first(where: { lines[$0].lowercased().hasPrefix(nameField.lowercased()) }) {
                        guard lines[index] != line else { continue }
                        lines[index] = line
                    } else {
                        var at = end
                        while at > start + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                        lines.insert(line, at: at)
                    }
                } else {
                    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
                    lines += ["", header + " \(now)", line, ""]
                }
                changed += 1
            }
        }
        return (lines.joined(separator: "\n"), changed)
    }

    /// Wine's escaping in .reg files: \\ and \", other characters beyond
    /// ASCII as \xNNNN.
    static func escape(_ text: String) -> String {
        var result = ""
        for unit in text.utf16 {
            switch unit {
            case 0x5c: result += "\\\\"
            case 0x22: result += "\\\""
            case 0x20..<0x7f: result.append(Character(Unicode.Scalar(unit)!))
            default: result += String(format: "\\x%04x", unit)
            }
        }
        return result
    }

    // MARK: Folders

    /// The Windows user's Documents (C:\users\<name>\Documents), as Wine
    /// recorded it under Shell Folders.
    static func documentsFolder(prefix: URL) -> String? {
        guard let data = try? Data(contentsOf: prefix.appendingPathComponent("user.reg")) else { return nil }
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        let header = "[software\\\\microsoft\\\\windows\\\\currentversion\\\\explorer\\\\shell folders]"
        guard let start = lines.firstIndex(where: { $0.lowercased().hasPrefix(header) }) else { return nil }
        for line in lines[(start + 1)...] {
            if line.hasPrefix("[") { break }
            if line.lowercased().hasPrefix("\"personal\"=\""), line.hasSuffix("\"") {
                let value = line.dropFirst("\"personal\"=\"".count).dropLast()
                return value.replacingOccurrences(of: "\\\\", with: "\\")
            }
        }
        return nil
    }

    /// A C:\ path on the drive, each existing part matched without regard to
    /// case (as Windows does). nil for other drives or a parent reference.
    static func unixPath(_ windows: String, drive: URL) -> URL? {
        let parts = windows.replacingOccurrences(of: "/", with: "\\").split(separator: "\\").map(String.init)
        guard let first = parts.first, first.caseInsensitiveCompare("C:") == .orderedSame,
              !parts.contains("..") else { return nil }
        var url = drive
        for part in parts.dropFirst() where part != "." {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            let match = names.first { $0 == part } ?? names.first { $0.caseInsensitiveCompare(part) == .orderedSame }
            url.appendPathComponent(match ?? part)
        }
        return url
    }

    /// Copies the files under `from` that `to` lacks. Returns how many.
    static func copyMissing(from: URL, to: URL) -> Int {
        let manager = FileManager.default
        guard let items = manager.enumerator(at: from, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return 0 }
        var copied = 0
        for case let item as URL in items {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, values.isDirectory != true else { continue }
            let base = from.resolvingSymlinksInPath().path + "/", path = item.resolvingSymlinksInPath().path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count))
            let target = to.appendingPathComponent(relative)
            guard !manager.fileExists(atPath: target.path) else { continue }
            do {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: item, to: target)
                copied += 1
            } catch {
                LogStore.shared.log("[akvavit-script] copy failed: \(relative): \(error.localizedDescription)", level: .error)
            }
        }
        return copied
    }
}
