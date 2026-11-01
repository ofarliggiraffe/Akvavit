// SPDX-License-Identifier: GPL-3.0-or-later
//
// JIT: what the interface needs to set up and enable JIT. Madeira's JIT code
// does the work (JITCoordinator, OnDevicePairing, StikJIT built in) through
// Akvavit's own VPN (AkvavitTunnel).

import Combine
import Foundation
import Observation

@MainActor @Observable
public final class JIT {
    public static let shared = JIT()

    public enum Pairing: Equatable {
        case idle
        case waiting
        /// The code to enter in Settings › Privacy & Security › Developer Mode.
        case code(String)
        case failed(String)
    }

    // Madeira's models publish their changes through Combine; each change bumps
    // `revision`, which every property below reads, so views redraw.
    private var revision = 0
    @ObservationIgnored private var watchers: [AnyCancellable] = []

    private init() {
        let bump: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.revision &+= 1 }
        }
        watchers = [
            JITCoordinator.shared.objectWillChange.sink { _ in bump() },
            OnDevicePairing.shared.objectWillChange.sink { _ in bump() },
            AkvavitTunnel.shared.objectWillChange.sink { _ in bump() },
        ]
    }

    // MARK: State

    /// The debugger is attached: Windows programs can start.
    public var isOn: Bool { _ = revision; return StikJITHelper.ready }
    /// A setup check or an enable is running.
    public var busy: Bool { _ = revision; return JITCoordinator.shared.busy }
    public var status: String? { _ = revision; return JITCoordinator.shared.status }
    public var error: String? { _ = revision; return JITCoordinator.shared.error }

    /// The app is signed so that a debugger may attach (a development signature).
    public var debuggable: Bool { SigningStatus.current.debuggable }

    // MARK: Setup, in order: pair, allow the VPN, check

    /// The device is paired: the app has a pairing file.
    public var paired: Bool { _ = revision; return JITCoordinator.shared.pairingImported }
    /// Pairing on the device itself (iOS 27 and later). Otherwise a pairing file
    /// made on a computer has to be imported.
    public var onDevicePairingSupported: Bool { OnDevicePairing.isSupported }
    /// The name the pairing request shows in Developer Mode.
    public var pairingHostName: String { OnDevicePairing.hostName }
    public var pairing: Pairing {
        _ = revision
        switch OnDevicePairing.shared.phase {
        case .idle, .paired: return .idle
        case .waiting: return .waiting
        case .pin(let code): return .code(code)
        case .failed(let why): return .failed(why)
        }
    }
    public func startPairing() { OnDevicePairing.shared.start() }
    public func cancelPairing() { OnDevicePairing.shared.cancel() }
    public func importPairingFile(_ url: URL) {
        JITCoordinator.shared.importPairingFile(url)
        if JITCoordinator.shared.pairingImported { JITCoordinator.shared.method = .builtIn }
    }

    /// iOS has the VPN configuration that JIT goes through.
    public var vpnInstalled: Bool { _ = revision; return AkvavitTunnel.shared.installed }
    public func installVPN() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            AkvavitTunnel.shared.install { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
    }

    /// Checks the connection and mounts Apple's Developer Disk Image when needed.
    /// The result shows in `busy`, `status` and `error`.
    public func checkSetup() {
        JITCoordinator.shared.method = .builtIn
        JITCoordinator.shared.prepareBuiltIn()
    }

    public func refresh() {
        JITCoordinator.shared.refreshPairingStatus()
        AkvavitTunnel.shared.refresh()
        revision &+= 1
    }

    // MARK: Enabling

    /// Attaches the debugger. Returns at once when JIT is already on.
    public func enable() async throws {
        if JITCoordinator.shared.method == .automatic { JITCoordinator.shared.method = .builtIn }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            JITCoordinator.shared.enable { result in done.resume(with: result) }
        }
        revision &+= 1
    }
}
