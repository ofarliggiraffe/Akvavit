// SPDX-License-Identifier: GPL-3.0-or-later
//
// What goes into the phone's backups (iCloud and a computer's), as the user
// chose (2026-11-02):
//
//   in:   the settings in Library: control layouts, game settings, the games
//         list (Application Support), and the preferences;
//   out:  everything in Documents: Windows with every game and its saves
//         (old games keep saves anywhere, so no rule could pick them out),
//         the logs, the JIT dump, the Files app's deleted items.
//
// Caches are never backed up, and the Steam and GOG sign-ins in the Keychain
// stay on this device. iOS has no switch for a whole app, and a folder loses
// its mark when it is made anew, so every item in Documents is marked at each
// start and whenever the app goes to the background (backups run while it is
// there).

import Foundation
import UIKit

enum Backup {
    @MainActor private static var observer: NSObjectProtocol?

    /// Marks Documents now and each time the app goes to the background.
    @MainActor static func begin() {
        excludeDocuments()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                          object: nil, queue: .main) { _ in excludeDocuments() }
    }

    /// Marks every item in Documents (hidden ones too) as left out of backups.
    static func excludeDocuments() {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let items = try? manager.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isExcludedFromBackupKey])
        else { return }
        var marked: [String] = []
        for var item in items {
            guard (try? item.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            do {
                try item.setResourceValues(values)
                marked.append(item.lastPathComponent)
            } catch {
                LogStore.shared.log("[backup] \(item.lastPathComponent) not left out: \(error.localizedDescription)", level: .error)
            }
        }
        if !marked.isEmpty {
            LogStore.shared.log("[backup] left out of backups: " + marked.sorted().joined(separator: ", "))
        }
    }
}
