// SPDX-License-Identifier: GPL-3.0-or-later
//
// A Windows session: one launch of Wine with one program. Everything a launch
// sets is in LaunchConfig and goes into the environment in one place
// (`environment(for:)`), where Madeira's engine reads it.
//
// The engine allows one session per app run: its wineserver runs inside the
// app and cannot be started a second time.

import Foundation
import Observation
import UIKit

public struct LaunchConfig: Sendable {
    public enum Program: Sendable {
        /// A program started directly: a name in C:\windows\system32
        /// ("cube.exe") or a full Windows path. Arguments use Windows quoting.
        case direct(executable: String, arguments: String = "", workingFolder: String? = nil)
        /// Windows' desktop (explorer), which then starts `executable`, if given.
        case desktop(executable: String? = nil)
    }

    public var program: Program
    /// The size of the Windows screen, in pixels.
    public var screenWidth: Int
    public var screenHeight: Int
    /// FEX computes x87 floating point in 64 instead of 80 bits: much faster for
    /// 32-bit Direct3D 8 games (Railroad Tycoon 3: 7 → 60 FPS).
    public var reducedPrecisionX87: Bool
    /// More variables, set last (so they win). For trying engine options.
    public var extraEnvironment: [String: String]

    public init(program: Program, screenWidth: Int = 1024, screenHeight: Int = 768,
                reducedPrecisionX87: Bool = false, extraEnvironment: [String: String] = [:]) {
        self.program = program
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.reducedPrecisionX87 = reducedPrecisionX87
        self.extraEnvironment = extraEnvironment
    }

    var isDesktop: Bool {
        if case .desktop = program { return true }
        return false
    }

    var displayName: String {
        switch program {
        case .direct(let executable, _, _):
            return executable.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? executable
        case .desktop(let executable):
            return executable.map { "Desktop (\($0))" } ?? "Desktop"
        }
    }
}

@MainActor @Observable
public final class Session {
    public static let shared = Session()

    public enum State: Equatable {
        case idle
        /// Starting, with what it is doing now.
        case starting(String)
        case running
        /// Ended; with the reason when it failed.
        case ended(String?)
    }

    public private(set) var state: State = .idle
    /// Frames the session has put on screen (Direct3D and OpenGL).
    public private(set) var framesPresented: UInt64 = 0
    /// The current session's config (or the last one's).
    public private(set) var config: LaunchConfig?

    /// A session already ran in this app run; another needs a restart.
    public var needsRestart: Bool { state != .idle }

    /// The Wine prefix: Documents/wine.
    public static var prefixURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wine")
    }

    private init() {}

    /// The JIT pool's size. Madeira's tested value; it costs this much memory
    /// from the start, used or not.
    private nonisolated static let poolMegabytes = 896

    public func start(_ config: LaunchConfig) {
        guard state == .idle else { return }
        guard JIT.shared.isOn else {
            state = .ended("JIT is off. Enable JIT first.")
            return
        }
        guard wineserver_is_running() == 0, wine_process_is_running() == 0 else {
            state = .ended("A session already ran in this app run. Close Akvavit and open it again.")
            return
        }
        self.config = config
        state = .starting("Preparing")
        AkvavitSessionLogs.prune()
        LogStore.shared.startSessionLog(program: config.displayName)
        LogStore.shared.log("[session] start \(config.displayName) screen=\(config.screenWidth)x\(config.screenHeight) "
                            + "x87-reduced=\(config.reducedPrecisionX87 ? 1 : 0)")

        let environment = Self.environment(for: config)
        for (name, value) in environment.sorted(by: { $0.key < $1.key }) {
            if let value { setenv(name, value, 1) } else { unsetenv(name) }
        }
        winios_display_mode_changed(Int32(config.screenWidth), Int32(config.screenHeight))
        // The wineserver's own os_log lines can block the main thread when there
        // are many; its file log stays.
        ws_log_quiet = 1
        UIApplication.shared.isIdleTimerDisabled = true
        // Hidden while starting, so the progress shows; it sits above the interface.
        GameLayerHost.shared.isHidden = true

        let prefix = Self.prefixURL.path
        Thread.detachNewThread { [weak self] in
            Self.run(prefix: prefix) { update in
                DispatchQueue.main.async { self?.apply(update) }
            }
        }
    }

    // MARK: The environment

    /// Every variable a launch sets or clears (nil clears: a value from an
    /// earlier launch in this process must not carry over).
    static func environment(for config: LaunchConfig) -> [String: String?] {
        var env: [String: String?] = [
            "MADEIRA_SCREEN_W": String(config.screenWidth),
            "MADEIRA_SCREEN_H": String(config.screenHeight),
            "FEX_X87REDUCEDPRECISION": config.reducedPrecisionX87 ? "1" : "0",
            // DXMT's memory report: at most every 10 s (its 32-bit default).
            "DXMT_CENSUS_THROTTLE": "1",
            // Metal's performance HUD without its notes over the game.
            "MTL_HUD_INSIGHTS_ENABLED": "0",
            // Controllers as Windows.Gaming.Input gamepads too.
            "MADEIRA_WGI_HOST_PADS": "1",
        ]
        switch config.program {
        case .direct(let executable, let arguments, let workingFolder):
            env["MADEIRA_EXE"] = .some(executable)
            env["MADEIRA_ARGS"] = .some(arguments.isEmpty ? nil : arguments)
            env["MADEIRA_WORKDIR"] = .some(workingFolder)
            env["MADEIRA_DESKTOP"] = .some(nil)
        case .desktop(let executable):
            // Explorer opens the desktop and starts one command line in it: the
            // program, else services.exe, which keeps an empty desktop running.
            // (Wine starts the services itself when a program needs them.)
            let size = "\(config.screenWidth)x\(config.screenHeight)"
            let arguments = "/desktop=shell,\(size) " + (executable ?? "C:\\windows\\system32\\services.exe")
            env["MADEIRA_EXE"] = .some("explorer.exe")
            env["MADEIRA_ARGS"] = .some(arguments)
            env["MADEIRA_WORKDIR"] = .some(nil)
            env["MADEIRA_DESKTOP"] = .some("1")
        }
        for (name, value) in config.extraEnvironment { env[name] = .some(value) }
        return env
    }

    // MARK: Running (on its own thread)

    enum Update {
        case step(String)
        case running
        case frames(UInt64)
        case ended(String?)
    }

    private nonisolated static func run(prefix: String, report: @escaping (Update) -> Void) {
        // 1. The JIT pool: executable memory the debugger prepares, which Wine
        //    and FEX put all translated code in. The debugger has to be attached.
        report(.step("Preparing JIT memory"))
        guard let pool = StikJITHelper.allocatePool(poolSize: poolMegabytes << 20) else {
            report(.ended(StikJITHelper.poolFailure ?? "The JIT memory could not be prepared."))
            return
        }
        setenv("WINE_IOS_JIT_RX", String(format: "%lx", Int(bitPattern: pool.rx)), 1)
        setenv("WINE_IOS_JIT_RW", String(format: "%lx", Int(bitPattern: pool.rw)), 1)
        setenv("WINE_IOS_JIT_SIZE", String(format: "%lx", pool.size), 1)
        setOrClear("WINE_IOS_JIT_HOLE", StikJITHelper.poolHole.map { String(format: "%lx:%lx", $0.off, $0.end) })
        setOrClear("WINE_IOS_JIT_HOLE2", StikJITHelper.poolHole2.map { String(format: "%lx:%lx", $0.off, $0.end) })
        setOrClear("WINE_IOS_JIT_TAIL_REGION", StikJITHelper.poolLow.map { String(format: "%lx:%lx", $0.rx, $0.size) })
        LogStore.shared.log(String(format: "[session] JIT pool rx=%p rw=%p %ld MB",
                                   Int(bitPattern: pool.rx), Int(bitPattern: pool.rw), pool.size >> 20))

        // 2. The debugger goes now, while the address space is still small:
        //    its later departure stalls the whole app for about a minute.
        report(.step("Detaching the debugger"))
        StikJITHelper.detachDebugger()

        // 3. The wineserver, as a thread of the app.
        report(.step("Starting Windows"))
        guard wineserver_start(prefix) == 0 else {
            report(.ended("The Windows server did not start."))
            return
        }
        let serverStart = Date()
        while wineserver_is_ready() == 0, wineserver_is_running() != 0, Date().timeIntervalSince(serverStart) < 5 {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard wineserver_is_running() != 0 else {
            report(.ended("The Windows server stopped while starting."))
            return
        }

        // 4. Wine, with the program from MADEIRA_EXE.
        guard wine_process_start(prefix) == 0 else {
            report(.ended("Windows did not start."))
            return
        }
        report(.running)

        // 5. Until the program ends.
        var lastFrames: UInt64 = 0
        while wine_process_is_running() != 0 {
            Thread.sleep(forTimeInterval: 0.25)
            let frames = madeira_frame_count()
            if frames != lastFrames {
                lastFrames = frames
                report(.frames(frames))
            }
        }
        var status: UInt32 = 0
        if wine_crash_exit_status(&status) != 0 {
            report(.ended(String(format: "The program stopped with an error (0x%08X).", status)))
        } else {
            report(.ended(nil))
        }
    }

    private nonisolated static func setOrClear(_ name: String, _ value: String?) {
        if let value { setenv(name, value, 1) } else { unsetenv(name) }
    }

    private func apply(_ update: Update) {
        switch update {
        case .step(let what): state = .starting(what)
        case .running:
            state = .running
            GameLayerHost.shared.isHidden = false
        case .frames(let count): framesPresented = count
        case .ended(let reason):
            state = .ended(reason)
            // The picture sits above the interface: it goes with the session.
            GameLayerHost.shared.isHidden = true
            _ = winios_compositor_set_hidden(1)
            ws_log_quiet = 0
            UIApplication.shared.isIdleTimerDisabled = false
            LogStore.shared.log("[session] ended" + (reason.map { ": \($0)" } ?? ""))
        }
    }
}
