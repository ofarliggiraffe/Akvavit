// SPDX-License-Identifier: GPL-3.0-or-later
//
// What a game's start is doing, for the loading screen, and when the game is
// up. Until then Windows' screen stays hidden (the game's picture and Wine's
// desktop), so the loading screen shows instead of Windows starting.
//
// The steps, in the order they happen:
// - JIT, and Steam's client files when they are missing: what Play does
//   before the session (the app reports them here, `prepare`).
// - Windows: the session's own start steps (Session).
// - One-time installs (starts that have any): the line the install batch
//   writes as each program starts and ends (DockInstallers' result file, or
//   GOGStart's in the same format; read with DockInstallScripts.results).
// - Steam: Madeira Dock's report (MadeiraDock.pollReport): signing in, the
//   licence, Steam starting the game, problems.
// - The game: up when a visible window that has drawn something belongs to a
//   program in the game's own folder, once the installs are done (installers
//   can live in the game's folder too), and it stays: still there and drawing
//   again a moment later (`settle`), or still there after `settleStill` for a
//   game that draws one picture and waits. Its going away starts the wait
//   over. The engine's window census says who owns each window. "Drawn": a
//   GDI frame of its own, or for a window that Direct3D draws into, a frame
//   the engine has actually presented (Portal's window had a swapchain well
//   before its first frame, and Wine's desktop showed in between). Anno 1602
//   drew one GDI frame, then hid its window while it set up DirectDraw: Wine's
//   desktop showed. A start without Steam is up at its first frame.
//
// A window with a title bar from any other program (an installer, Steam's
// client; not Wine's own, under C:\windows\) may need an answer: the loading
// screen says so and can show Windows' screen until that window closes.

import Foundation
import Observation
import UIKit

@MainActor @Observable
public final class StartProgress {
    public static let shared = StartProgress()

    public enum Step: Hashable, Sendable {
        case jit, clientFiles, windows, installs, steam, game
    }

    public enum Status: Equatable, Sendable {
        case waiting, now, done, failed
    }

    public struct Line: Equatable, Sendable {
        public var status: Status
        public var detail: String
    }

    /// A window that may need an answer.
    public struct Asking: Equatable, Sendable {
        public var title: String
        public var detail: String
        fileprivate var window: UInt64
    }

    /// This start's steps, in order.
    public private(set) var steps: [Step] = []
    /// The steps' lines as the loading screen shows them: when several change
    /// at once (the app pauses while the debugger works, then catches up),
    /// they show one after another (`tickGap`).
    public private(set) var lines: [Step: Line] = [:]
    /// The game is up: the loading screen goes and the game shows.
    public private(set) var gameIsUp = false
    public private(set) var asking: Asking?
    /// Windows' screen is shown on request (Show it, or the test menu) before
    /// the game is up.
    public private(set) var showingWindows = false

    /// Whether the loading screen covers Windows' screen now.
    public var covers: Bool { !steps.isEmpty && !gameIsUp && !showingWindows }
    /// The game starting, from the Play tap (before the session knows it).
    public private(set) var game: Game?
    /// Play's own steps run; the session hasn't started.
    public private(set) var beforeSession = false
    /// The session ended with a problem before the game was up: the loading
    /// screen says so and offers to close the app (Windows starts once per run).
    public private(set) var stopped = false
    /// One of Play's own steps failed: the loading screen offers Back.
    public var failedBeforeSession: Bool {
        beforeSession && lines.values.contains { $0.status == .failed }
    }

    // This start.
    @ObservationIgnored private var desktop = false
    @ObservationIgnored private var gameFolder: String?
    @ObservationIgnored private var installsRunning = false
    /// Where the installs write their progress (Dock's file unless given).
    @ObservationIgnored private var installsResult: URL?
    /// When a game window was first seen drawn, and how much it had drawn.
    @ObservationIgnored private var sighting: (time: Date, draws: UInt64)?
    @ObservationIgnored private var timer: Timer?
    /// The window Show it revealed: covered again when it goes.
    @ObservationIgnored private var shownWindow: UInt64?
    /// Counts starts, so a late step of one start changes nothing in the next.
    @ObservationIgnored private var startNumber = 0
    /// The steps before the session's own (Play's).
    @ObservationIgnored private var before: [Step] = []
    /// The steps' lines as they are now (`lines` follows, paced).
    @ObservationIgnored private var truth: [Step: Line] = [:]
    @ObservationIgnored private var pending: [(Step, Line)] = []
    @ObservationIgnored private var lastShown = Date.distantPast
    @ObservationIgnored private var pacing = false
    private static let tickGap: TimeInterval = 0.3

    private init() {}

    // MARK: From Play

    /// Play was pressed for `game`: its own steps (JIT, and Steam's client
    /// files when `clientFiles`) come first, then the session's.
    public func prepare(_ game: Game, clientFiles: Bool) {
        reset(before: [.jit] + (clientFiles ? [.clientFiles] : []), steam: game.source == .steam)
        self.game = game
        beforeSession = true
        set(.jit, .now, "Turning on")
    }

    /// One of Play's steps: now, done or failed.
    public func report(_ step: Step, _ status: Status, _ detail: String) {
        set(step, status, detail)
    }

    /// Back, after one of Play's steps failed: the loading screen goes.
    public func back() {
        ended()
    }

    // MARK: From Session

    /// A session starts. `steam`: through Madeira Dock; `desktop`: on Windows' desktop.
    func begin(steam: Bool, desktop: Bool) {
        if !beforeSession { reset(before: [], steam: steam) }
        beforeSession = false
        self.desktop = desktop
        set(.windows, .now, "Getting ready")
        applyVisibility()
    }

    private func reset(before: [Step], steam: Bool) {
        stop()
        startNumber += 1
        self.before = before
        game = nil
        stopped = false
        gameFolder = nil
        installsResult = nil
        sighting = nil
        gameIsUp = false
        asking = nil
        showingWindows = false
        shownWindow = nil
        steps = before + (steam ? [.windows, .steam, .game] : [.windows, .game])
        pending = []
        pacing = false
        lastShown = .distantPast
        truth = [:]
        for step in steps { truth[step] = Line(status: .waiting, detail: Self.waitingWords(step)) }
        lines = truth
    }

    /// The game's folder (its Windows path), and whether one-time installs
    /// run first; `installsOnly`: they are all this session runs.
    func prepared(gameFolder: String, installs: Bool, installsOnly: Bool, result: URL? = nil) {
        self.gameFolder = gameFolder.lowercased().hasSuffix("\\") ? gameFolder.lowercased() : gameFolder.lowercased() + "\\"
        installsRunning = installs
        installsResult = result
        if installsOnly {
            steps = before + [.windows, .installs]
        } else if installs {
            steps = before + [.windows, .installs] + (steps.contains(.steam) ? [.steam] : []) + [.game]
        }
        if installs {
            truth[.installs] = Line(status: .waiting, detail: "What the game needs")
            lines[.installs] = truth[.installs]
        }
    }

    /// One of Windows' own start steps: the line stays plain ("Starting");
    /// the log has the details.
    func windowsStep(_ what: String) {
        set(.windows, .now, "Starting")
    }

    /// Windows is running: watch for the game from here.
    func running() {
        set(.windows, .done, "Ready")
        if steps.contains(.installs) {
            set(.installs, .now, "Getting ready")
        } else if steps.contains(.steam) {
            set(.steam, .now, "Starting Steam")
        } else {
            set(.game, .now, "Starting game")
        }
        if desktop { winios_window_census_enable(1) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { StartProgress.shared.tick() }
        }
        tick()
    }

    /// The session ended. Before the game was up, with `failure`: the step it
    /// happened in fails with it, and the loading screen stays to say so
    /// (`stopped`); otherwise the loading screen goes.
    func ended(failure: String? = nil) {
        stop()
        if desktop { winios_window_census_enable(0) }
        beforeSession = false
        asking = nil
        showingWindows = false
        if let failure, !gameIsUp, !steps.isEmpty {
            let step = steps.first { truth[$0]?.status == .now }
                ?? steps.first { truth[$0]?.status != .done } ?? steps[steps.count - 1]
            set(step, .failed, failure)
            stopped = true
        } else {
            steps = []
        }
    }

    // MARK: From the loading screen

    /// Show it: Windows' screen until the window that asks closes.
    public func showAsking() {
        shownWindow = asking?.window
        showingWindows = true
        applyVisibility()
    }

    /// Windows' screen on or off before the game is up (the test menu).
    public func setShowingWindows(_ on: Bool) {
        shownWindow = nil
        showingWindows = on
        applyVisibility()
    }

    // MARK: Watching

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !gameIsUp else { return stop() }
        if steps.contains(.installs) { readInstalls() }
        if steps.contains(.steam) { readSteam() }
        let windows = desktop ? census() : []
        if desktop, gameFolder != nil {
            if steps.contains(.game), !installsRunning, truth[.steam]?.status != .failed,
               let window = windows.first(where: { isGame($0) }) {
                // Everything the game's windows have drawn so far.
                let draws = windows.filter { isGame($0) }.reduce(UInt64(Session.shared.framesPresented)) { $0 + UInt64($1.presents) }
                guard let seen = sighting else {
                    sighting = (Date(), draws)
                    LogStore.shared.log("[start] game window seen \(window.program) \(window.width)x\(window.height) "
                                        + "gdi-frames=\(window.presents) direct3d=\(window.metal ? 1 : 0)")
                    return applyVisibility()
                }
                let waited = Date().timeIntervalSince(seen.time)
                guard (waited >= Self.settle && draws > seen.draws) || waited >= Self.settleStill else {
                    return applyVisibility()
                }
                LogStore.shared.log("[start] game window \(window.program) \(window.width)x\(window.height) "
                                    + "gdi-frames=\(window.presents) direct3d=\(window.metal ? 1 : 0) "
                                    + "frames=\(Session.shared.framesPresented) after \(String(format: "%.1f", waited)) s")
                return gameUp()
            } else if sighting != nil {
                // The game's window went (a game switching its screen mode): wait again.
                sighting = nil
                LogStore.shared.log("[start] game window gone again")
            }
            findAsking(windows)
        } else if Session.shared.framesPresented > 0 || (desktop && winios_surface_present_count() > 0) {
            return gameUp()
        }
        applyVisibility()
    }

    /// The last tick shows for a moment, so the whole list is seen done; then
    /// the loading screen goes and the game shows.
    private func gameUp() {
        set(.game, .done, "Ready")
        asking = nil
        showingWindows = false
        stop()
        // The census only goes on restoring windows first shown minimized.
        if desktop { winios_window_census_enable(2) }
        LogStore.shared.log("[start] the game is up")
        let start = startNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + pacedFor + Self.doneMoment) {
            MainActor.assumeIsolated {
                let progress = StartProgress.shared
                guard progress.startNumber == start, !progress.steps.isEmpty else { return }
                progress.gameIsUp = true
                progress.applyVisibility()
            }
        }
    }

    /// How long the finished list shows before the game.
    private static let doneMoment: TimeInterval = 0.9
    /// How long a game window must stay and draw again before the game is up.
    private static let settle: TimeInterval = 1.0
    /// How long a game window that doesn't draw again must stay.
    private static let settleStill: TimeInterval = 4.0

    /// Windows' screen (the game's picture, and on a desktop Wine's desktop) is
    /// hidden while the loading screen covers it. Done on every tick: the
    /// desktop's view may be made after the start.
    private func applyVisibility() {
        let hide = covers
        GameLayerHost.shared.isHidden = hide
        // A game session's own view goes when hidden; only a desktop's is hidden.
        if desktop { _ = winios_compositor_set_hidden(hide ? 1 : 0) }
    }

    // MARK: The steps

    private func readInstalls() {
        guard installsRunning || truth[.installs]?.status == .now else { return }
        let file = installsResult ?? MadeiraDock.drive.appendingPathComponent(DockInstallers.resultName)
        guard let data = try? Data(contentsOf: file), data.count <= 16384 else { return }
        let results = DockInstallScripts.results(String(decoding: data, as: UTF8.self))
        if let running = results.running {
            let name = results.started[running].map { $0.isEmpty ? "A program" : $0 } ?? "A program"
            set(.installs, .now, "Installing \(name) · \(running) of \(max(results.total, running))")
        } else if results.ended {
            installsRunning = false
            let failed = results.exits.values.filter { !DockInstallScripts.Results.succeeded($0) }.count
            set(.installs, .done, failed == 0 ? "Done" : "Done, \(failed) of \(max(results.total, results.exits.count)) didn't finish")
            if steps.contains(.steam), truth[.steam]?.status == .waiting {
                set(.steam, .now, "Starting Steam")
            } else if !steps.contains(.steam), truth[.game]?.status == .waiting {
                set(.game, .now, "Starting game")
            }
        }
    }

    private func readSteam() {
        guard truth[.steam]?.status == .now else { return }
        let report = MadeiraDock.pollReport()
        if let failure = report.failure ?? Session.shared.dockProblem {
            set(.steam, .failed, failure)
            return
        }
        let fields = report.fields
        if fields["launch-client-error"] == "0" {
            set(.steam, .done, "Done")
            set(.game, .now, "Starting game")
        } else if fields["launch-update-wait"] != nil, fields["launch-update-ready"] == nil {
            set(.steam, .now, "Updating the game")
        } else if ["ceg-scm", "ceg-request-busy", "ceg-request"].contains(where: { fields[$0] != nil }), fields["ceg-result"] == nil {
            set(.steam, .now, "Preparing the game")
        } else if fields["session-requested-app-listed"] == "1" || fields["session-offline-listed"] == "1" {
            set(.steam, .now, "Signed in")
        } else if fields["session-authenticated-online"] == "1" {
            set(.steam, .now, "Signing in")
        } else if fields["session-offline-requested"] != nil {
            set(.steam, .now, "Starting offline")
        } else if fields["session-native-token-submitted"] != nil || fields["session-logon-start-result"] != nil {
            set(.steam, .now, "Signing in")
        }
    }

    // MARK: Windows

    private struct Window {
        let id: UInt64
        let program: String
        let visible: Bool
        let presents: UInt32
        let metal: Bool
        let caption: Bool
        let width: Int32
        let height: Int32
    }

    private func census() -> [Window] {
        var raw = [winios_census_window](repeating: winios_census_window(), count: Int(WINIOS_CENSUS_MAX))
        let count = Int(winios_window_census(&raw, Int32(raw.count)))
        return raw.prefix(max(count, 0)).map { window in
            let program = withUnsafeBytes(of: window.image) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return Window(id: window.hwnd, program: program, visible: window.visible != 0,
                          presents: window.presents, metal: window.metal != 0, caption: window.caption != 0,
                          width: window.w, height: window.h)
        }
    }

    private func isGame(_ window: Window) -> Bool {
        guard let gameFolder else { return false }
        let drawn = window.presents > 0 || (window.metal && Session.shared.framesPresented > 0)
        return window.visible && drawn && window.program.hasPrefix(gameFolder)
    }

    /// A visible window with a title bar from a program other than Wine's own
    /// and, once the installs are done, other than the game's.
    private func findAsking(_ windows: [Window]) {
        let candidate = windows.first { window in
            window.visible && window.caption && !window.program.isEmpty && !window.program.hasPrefix("c:\\windows\\")
                && (installsRunning || !(gameFolder.map { window.program.hasPrefix($0) } ?? false))
        }
        if showingWindows, let shown = shownWindow, !windows.contains(where: { $0.id == shown && $0.visible }) {
            // The window that asked has gone: the loading screen comes back.
            showingWindows = false
            shownWindow = nil
        }
        guard let candidate else {
            if asking != nil { asking = nil }
            return
        }
        guard asking?.window != candidate.id else { return }
        if installsRunning {
            let detail = truth[.installs]?.detail ?? ""
            let name = detail.hasPrefix("Installing ")
                ? String(detail.dropFirst("Installing ".count).prefix { $0 != "·" }).trimmingCharacters(in: .whitespaces)
                : "An installer"
            asking = Asking(title: "An installer is asking something",
                            detail: "\(name), one of the game's one-time installs, has a window open that may need an answer.",
                            window: candidate.id)
        } else if candidate.program.contains("\\steam\\") && !candidate.program.contains("\\steamapps\\") {
            asking = Asking(title: "Steam is asking something",
                            detail: "Steam has a window open that may need an answer.", window: candidate.id)
        } else {
            asking = Asking(title: "A window is asking something",
                            detail: "A program has a window open that may need an answer.", window: candidate.id)
        }
        LogStore.shared.log("[start] a window may need an answer: \(candidate.program)")
    }

    // MARK: Lines

    private func set(_ step: Step, _ status: Status, _ detail: String) {
        guard steps.contains(step) else { return }
        let line = Line(status: status, detail: detail)
        guard truth[step] != line else { return }
        truth[step] = line
        LogStore.shared.log("[start] \(step) \(status): \(detail)")
        pending.append((step, line))
        pace()
    }

    /// Shows the next pending line once `tickGap` has passed since the last.
    private func pace() {
        guard !pacing, !pending.isEmpty else { return }
        let wait = Self.tickGap - Date().timeIntervalSince(lastShown)
        guard wait > 0 else {
            let (step, line) = pending.removeFirst()
            lines[step] = line
            lastShown = Date()
            return pace()
        }
        pacing = true
        let start = startNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            MainActor.assumeIsolated {
                let progress = StartProgress.shared
                guard progress.startNumber == start else { return }
                progress.pacing = false
                progress.pace()
            }
        }
    }

    /// Until every pending line has shown.
    private var pacedFor: TimeInterval {
        guard !pending.isEmpty else { return 0 }
        return Double(pending.count - 1) * Self.tickGap + max(0, Self.tickGap - Date().timeIntervalSince(lastShown))
    }

    private static func waitingWords(_ step: Step) -> String {
        switch step {
        case .jit: "Turning on"
        case .clientFiles: "Downloading, once"
        case .windows: "Getting ready"
        case .installs: "What the game needs"
        case .steam: "Signing in"
        case .game: "Starting game"
        }
    }
}
