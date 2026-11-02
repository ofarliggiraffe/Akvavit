// SPDX-License-Identifier: GPL-3.0-or-later
//
// Starting a GOG game. GOG games have no copy protection: no client, no Dock;
// Windows' desktop starts the game itself. What to start comes from the game's
// own goggame-<id>.info (in every build, from GOG's depot): its primary
// "FileTask" names the program, its arguments and its working folder,
// relative to the game's folder.
//
// Windows' desktop starts one command line, so the session runs a start file
// of ours, drive_c/GOG Games/.akvavit/start-<id>.cmd, which first runs the
// installers of what the game needs (Visual C++, OpenAL…) that haven't run in
// this prefix yet, then goes to the working folder and starts the game.
//
// The installers write their progress into installs.result, in Madeira
// Dock's format (begin N, start i name, exit i status, end), which the
// loading screen reads (StartProgress). At the next Play, the ones that
// succeeded go into dependencies.json and don't run again. What this build
// supplies itself (Visual C++ 14, DirectX, .NET Framework with Wine Mono)
// never runs: the rules Steam games use (AkvavitInstallScripts).

import Foundation

public enum GOGStart {
    public enum Failure: LocalizedError {
        case notInstalled
        case noProgram

        public var errorDescription: String? {
            switch self {
            case .notInstalled: "The game isn't installed."
            case .noProgram: "The game's files don't say which program starts it (goggame info)."
            }
        }
    }

    /// The parts of goggame-<id>.info a start needs.
    private struct Info: Decodable {
        struct Task: Decodable {
            let category: String?
            let isPrimary: Bool?
            let type: String?
            let path: String?
            let arguments: String?
            let workingDir: String?
        }
        let playTasks: [Task]?
    }

    /// Where Windows sees GOG games.
    private static let windowsRoot = "C:\\GOG Games"

    /// The game's folder, as Windows sees it.
    static func windowsFolder(_ record: GOGInstalls.Record) -> String {
        windowsRoot + "\\" + record.folder.replacingOccurrences(of: "/", with: "\\")
    }

    /// The command line the session runs (the start file).
    static func command(_ id: Int) -> String {
        "C:\\windows\\system32\\cmd.exe /c \"\(windowsRoot)\\.akvavit\\start-\(id).cmd\""
    }

    /// What of GOG's dependencies this build supplies itself.
    static func supplied(_ id: String) -> AkvavitInstallScripts.Supplied? {
        let id = id.lowercased()
        if id.hasPrefix("msvc"), let year = Int(id.dropFirst(4).prefix(4)), year >= 2015 { return .visualCpp14 }
        if id == "directx" { return .directX }
        // .NET Framework, not .NET (Core) or its desktop runtime.
        if id.hasPrefix("dotnet"), !id.hasPrefix("dotnetcore"), !id.hasPrefix("dotnetdesktop") { return .dotNet }
        return nil
    }

    // Files for the whole prefix, beside our records.
    private static var ledgerFile: URL { GOGInstalls.records.appendingPathComponent("dependencies.json") }
    private static var planFile: URL { GOGInstalls.records.appendingPathComponent("installs.plan.json") }
    static var resultFile: URL { GOGInstalls.records.appendingPathComponent("installs.result") }
    private static let windowsResult = windowsRoot + "\\.akvavit\\installs.result"

    /// The installers that have run in this prefix, by GOG's ID.
    private struct Ledger: Codable { var ran: Set<String> = [] }

    /// The installs result file when the next start runs installers first.
    static func pendingInstallsResult(_ id: Int) -> URL? {
        FileManager.default.fileExists(atPath: planFile.path) ? resultFile : nil
    }

    /// The last start's installers that succeeded go into the ledger.
    private static func recordFinishedInstalls() {
        defer {
            try? FileManager.default.removeItem(at: planFile)
            try? FileManager.default.removeItem(at: resultFile)
        }
        guard let plan = GOGInstalls.read([String].self, planFile),
              let data = try? Data(contentsOf: resultFile) else { return }
        let results = DockInstallScripts.results(String(decoding: data, as: UTF8.self))
        var ledger = GOGInstalls.read(Ledger.self, ledgerFile) ?? Ledger()
        for (index, status) in results.exits where index >= 1 && index <= plan.count {
            let succeeded = DockInstallScripts.Results.succeeded(status)
            if succeeded { ledger.ran.insert(plan[index - 1]) }
            LogStore.shared.log("[gog] installer \(plan[index - 1]) ended with \(status)" + (succeeded ? "" : ", runs again next time"))
        }
        try? GOGInstalls.write(ledger, to: ledgerFile)
    }

    /// Writes the start file for game `id`. Throws when it can't be started.
    @MainActor public static func prepare(_ id: Int) throws {
        recordFinishedInstalls()
        guard let record = GOGInstalls.record(id) else { throw Failure.notInstalled }
        let folder = GOGInstalls.folder(record.folder)
        let infoFile = folder.appendingPathComponent("goggame-\(id).info")
        guard let data = try? Data(contentsOf: infoFile),
              let info = try? JSONDecoder().decode(Info.self, from: data) else { throw Failure.noProgram }
        let programs = (info.playTasks ?? []).filter { $0.type == "FileTask" && ($0.path ?? "").isEmpty == false }
        guard let task = programs.first(where: { $0.isPrimary == true && $0.category != "document" })
                ?? programs.first(where: { $0.category == "game" }),
              let path = task.path else { throw Failure.noProgram }

        let gameFolder = windowsFolder(record)
        let program = gameFolder + "\\" + path.replacingOccurrences(of: "/", with: "\\")
        let working = task.workingDir.flatMap { $0.isEmpty ? nil : $0 }
            .map { gameFolder + "\\" + $0.replacingOccurrences(of: "/", with: "\\") } ?? gameFolder
        // `%` is cmd's variable sign in a batch file; arguments stay as GOG gives them.
        func batch(_ text: String) -> String { text.replacingOccurrences(of: "%", with: "%%") }
        var lines = [
            "@echo off",
            // The file is UTF-8: folder names may have letters beyond ASCII.
            "chcp 65001 >nul",
            "rem Written by Akvavit: starts \(batch(record.name)).",
        ]

        // The installers not run yet, each waited for (cmd waits for a
        // program a batch file starts), with its exit status written down.
        let ran = GOGInstalls.read(Ledger.self, ledgerFile)?.ran ?? []
        let available = AkvavitInstallScripts.available
        let pending = (record.installers ?? []).filter { installer in
            !ran.contains(installer.id) && !(supplied(installer.id).map(available.contains) ?? false)
                && FileManager.default.fileExists(atPath: folder.appendingPathComponent(installer.program).path)
        }
        if !pending.isEmpty {
            let result = "\"\(windowsResult)\""
            lines.append(">\(result) echo begin \(pending.count)")
            for (index, installer) in pending.enumerated() {
                let path = gameFolder + "\\" + installer.program.replacingOccurrences(of: "/", with: "\\")
                let name = installer.name.filter { $0.isLetter || $0.isNumber || " .+-()".contains($0) }
                lines.append(">>\(result) echo start \(index + 1) \(name)")
                lines.append("cd /d \"\(batch(String(path[..<path.lastIndex(of: "\\")!])))\"")
                lines.append(path.lowercased().hasSuffix(".msi")
                    ? "msiexec /i \"\(batch(path))\" \(batch(installer.arguments))"
                    : "\"\(batch(path))\" \(batch(installer.arguments))")
                lines.append(">>\(result) echo exit \(index + 1) %errorlevel%")
            }
            lines.append(">>\(result) echo end")
            try GOGInstalls.write(pending.map(\.id), to: planFile)
            LogStore.shared.log("[gog] start \(id) installs first: " + pending.map(\.id).joined(separator: ", "))
        }

        lines += [
            "cd /d \"\(batch(working))\"",
            "start \"\" /d \"\(batch(working))\" \"\(batch(program))\" \(batch(task.arguments ?? ""))",
        ]
        let file = GOGInstalls.root.appendingPathComponent(".akvavit/start-\(id).cmd")
        try Data((lines.joined(separator: "\r\n") + "\r\n").utf8).write(to: file, options: .atomic)
        LogStore.shared.log("[gog] start \(id): \(program) in \(working)"
                            + ((task.arguments ?? "").isEmpty ? "" : " args \(task.arguments!)"))
    }
}
