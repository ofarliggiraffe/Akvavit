// SPDX-License-Identifier: GPL-3.0-or-later
//
// First-start setup: whether it is done, and its JIT step, which runs as one
// chain: pairing (in Developer Mode) → the VPN (iOS asks) → the check →
// ready. Each part starts the next by itself; one that is already done is
// skipped. Steam's sign-in is `Steam`'s.

import Foundation
import Observation

@MainActor @Observable
public final class SetupFlow {
    public static let shared = SetupFlow()

    private static let doneKey = "akvavit.setupDone"

    /// Setup has been finished once (or skipped by running it again later).
    public private(set) var isDone: Bool

    public enum JITProgress: Equatable {
        case idle
        /// Waiting for the code to be entered in Developer Mode.
        case pairing
        /// iOS asks whether the VPN may be added.
        case allowingVPN
        case checking
        case ready
    }

    public private(set) var jitProgress = JITProgress.idle
    /// Why the chain stopped, in words.
    public private(set) var jitError: String?
    @ObservationIgnored private var jitTask: Task<Void, Never>?
    /// Tells a cancelled chain's end from the current one's.
    @ObservationIgnored private var jitRun = 0

    private init() {
        isDone = UserDefaults.standard.bool(forKey: Self.doneKey)
    }

    public func finish() {
        isDone = true
        UserDefaults.standard.set(true, forKey: Self.doneKey)
    }

    /// Settings › Run setup again.
    public func runAgain() {
        jitProgress = JIT.shared.isOn ? .ready : .idle
        jitError = nil
        isDone = false
        UserDefaults.standard.set(false, forKey: Self.doneKey)
    }

    // MARK: JIT

    public var jitRunning: Bool { jitTask != nil }
    /// JIT works: the check passed in this setup, or the debugger is attached.
    public var jitReady: Bool { jitProgress == .ready || JIT.shared.isOn }

    public func startJIT() {
        guard jitTask == nil else { return }
        jitError = nil
        jitRun += 1
        let run = jitRun
        jitTask = Task { [weak self] in
            await self?.runJIT()
            if self?.jitRun == run { self?.jitTask = nil }
        }
    }

    /// A pairing file made on a computer, instead of pairing here.
    public func usePairingFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        JIT.shared.importPairingFile(url)
        if access { url.stopAccessingSecurityScopedResource() }
        guard JIT.shared.paired else {
            jitError = JIT.shared.error ?? "That file isn't a pairing file for this device."
            return
        }
        startJIT()
    }

    public func cancelJIT() {
        jitTask?.cancel()
        jitTask = nil
        if case .pairing = jitProgress { JIT.shared.cancelPairing() }
        jitProgress = .idle
    }

    private func runJIT() async {
        let jit = JIT.shared
        if !jit.paired {
            jitProgress = .pairing
            jit.startPairing()
            var started = false
            while !jit.paired {
                if Task.isCancelled { return }
                switch jit.pairing {
                case .failed(let why):
                    stop("Pairing didn't work. " + why)
                    return
                case .idle where started:
                    // Cancelled, or it ended without a pairing.
                    stop(nil)
                    return
                case .waiting, .code:
                    started = true
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        if !jit.vpnInstalled {
            jitProgress = .allowingVPN
            do {
                try await jit.installVPN()
            } catch {
                stop("The VPN wasn't allowed. " + error.localizedDescription)
                return
            }
        }
        if Task.isCancelled { return }
        jitProgress = .checking
        if let problem = await jit.runCheck() {
            stop(problem)
            return
        }
        jitProgress = .ready
    }

    private func stop(_ problem: String?) {
        jitError = problem
        jitProgress = .idle
    }

    // MARK: Steam

    /// After signing in: Valve's client files download in the background, so
    /// the first Play needn't wait for them.
    public func prepareSteamClient() {
        let steam = Steam.shared
        guard !steam.clientReady, steam.clientProgress == nil else { return }
        Task { try? await steam.prepareClient() }
    }
}
