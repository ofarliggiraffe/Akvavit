// SPDX-License-Identifier: GPL-3.0-or-later
//
// Downloads go on when the app is left: a continued processing task
// (BackgroundTasks, iOS 26). iOS shows its progress in a Live Activity (the
// Dynamic Island), where it can also be stopped. One task covers the
// download queue; it ends when the queue is empty.
//
// It has to be asked for at a tap (Install), while the app is in front.
// Identifiers: <bundle ID>.download.<unique>, as Info.plist permits.

import BackgroundTasks
import Foundation

@MainActor
final class DownloadActivity {
    static let shared = DownloadActivity()

    private var task: BGContinuedProcessingTask?
    private var submitted = false
    /// The latest state, for a task that starts after it changed.
    private var title = ""
    private var subtitle = "Starting"
    private var fraction = 0.0
    /// The download the progress belongs to: within one, it never goes back.
    private var job: Int?
    /// What iOS was last told, so only changes are sent.
    private var shownTitle: String?
    private var shownSubtitle: String?

    private init() {}

    /// Asks iOS for the background task, unless one runs or is coming.
    func begin(title: String) {
        guard task == nil, !submitted, let bundleID = Bundle.main.bundleIdentifier else { return }
        self.title = title
        subtitle = "Starting"
        fraction = 0
        let identifier = "\(bundleID).download.\(UUID().uuidString.prefix(8))"
        // Each identifier is registered once: iOS ends an app that registers one twice.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { DownloadActivity.shared.started(task) }
        }
        guard registered else {
            SteamLog.event("[akvavit-steam] background download: not registered")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        // Now or not at all: a queued request could start after the download ended.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            submitted = true
        } catch {
            SteamLog.event("[akvavit-steam] background download: not submitted (\(error.localizedDescription))")
        }
    }

    private func started(_ backgroundTask: BGTask) {
        submitted = false
        guard let backgroundTask = backgroundTask as? BGContinuedProcessingTask else {
            backgroundTask.setTaskCompleted(success: false)
            return
        }
        task = backgroundTask
        backgroundTask.progress.totalUnitCount = 100
        // The downloads may have ended before iOS started the task.
        guard Steam.shared.hasQueuedDownloads else {
            end(success: true)
            return
        }
        // Stopped in the Live Activity, or iOS needs the resources: the
        // downloads stop and keep their files (Install resumes them).
        backgroundTask.expirationHandler = {
            Task { @MainActor in
                SteamLog.event("[akvavit-steam] background download: stopped by iOS or in the Live Activity")
                Steam.shared.stopAllDownloads()
                DownloadActivity.shared.end(success: false)
            }
        }
        apply()
    }

    /// The first download in line (`job`): its name, step and progress.
    /// iOS ends tasks whose progress looks stuck, so it only grows within
    /// one download.
    func update(job: Int, title: String, subtitle: String, fraction: Double) {
        if job != self.job {
            self.job = job
            self.fraction = 0
        }
        self.title = title
        self.subtitle = subtitle
        self.fraction = max(self.fraction, min(max(fraction, 0), 1))
        apply()
    }

    private func apply() {
        guard let task else { return }
        if title != shownTitle || subtitle != shownSubtitle {
            task.updateTitle(title, subtitle: subtitle)
            shownTitle = title
            shownSubtitle = subtitle
        }
        // Whole percent: fewer updates for iOS's display.
        let completed = Int64(fraction * 100)
        if completed > task.progress.completedUnitCount { task.progress.completedUnitCount = completed }
    }

    /// No download left.
    func end(success: Bool) {
        if let task {
            if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
            task.setTaskCompleted(success: success)
        }
        task = nil
        job = nil
        shownTitle = nil
        shownSubtitle = nil
    }
}
