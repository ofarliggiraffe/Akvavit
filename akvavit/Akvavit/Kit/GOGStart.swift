// SPDX-License-Identifier: GPL-3.0-or-later
//
// Starting a GOG game. GOG games have no copy protection: no client, no Dock;
// Windows' desktop starts the game itself. What to start comes from the game's
// own goggame-<id>.info (in every build, from GOG's depot): its primary
// "FileTask" names the program, its arguments and its working folder,
// relative to the game's folder.
//
// Windows' desktop starts one command line, so the session runs a start file
// of ours, drive_c/GOG Games/.akvavit/start-<id>.cmd, which goes to the
// working folder and starts the game. (Step 4 puts the one-time installs of
// what the game needs in front of it.)

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

    /// Writes the start file for game `id`. Throws when it can't be started.
    public static func prepare(_ id: Int) throws {
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
        let lines = [
            "@echo off",
            // The file is UTF-8: folder names may have letters beyond ASCII.
            "chcp 65001 >nul",
            "rem Written by Akvavit: starts \(batch(record.name)).",
            "cd /d \"\(batch(working))\"",
            "start \"\" /d \"\(batch(working))\" \"\(batch(program))\" \(batch(task.arguments ?? ""))",
        ]
        let file = GOGInstalls.root.appendingPathComponent(".akvavit/start-\(id).cmd")
        try Data((lines.joined(separator: "\r\n") + "\r\n").utf8).write(to: file, options: .atomic)
        LogStore.shared.log("[gog] start \(id): \(program) in \(working)"
                            + ((task.arguments ?? "").isEmpty ? "" : " args \(task.arguments!)"))
    }
}
