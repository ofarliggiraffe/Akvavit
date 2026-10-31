// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeps Documents/logs to the newest 40 session logs for Madeira Dock starts too.
//
// Madeira keeps a log per run under the program's name (LogStore.startSessionLog, which
// keeps the newest 40). A Steam game started through Madeira Dock gets its log from ntdll
// instead (process_ios.c, madeira_steam_session_log), which never removes old ones, so
// they piled up without limit (91 files, 155 MB on the device, 2026-10-31). The same rule
// now runs before each Dock start.
//
// Hook in Madeira's ContentView.swift, marked "Akvavit:": startDock.

import Foundation

enum AkvavitSessionLogs {
    /// Removes all but the newest `keep` session logs (by modification date), as
    /// LogStore.startSessionLog does.
    static func prune(keep: Int = 40) {
        let fm = FileManager.default
        let dir = LogStore.shared.logURL.deletingLastPathComponent().appendingPathComponent("logs", isDirectory: true)
        let runs = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "txt" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
        let old = runs.dropFirst(keep)
        guard !old.isEmpty else { return }
        var removed = 0
        for url in old where (try? fm.removeItem(at: url)) != nil { removed += 1 }
        LogStore.shared.log("[session-log] removed \(removed) old session log(s), kept the newest \(keep)")
    }
}
