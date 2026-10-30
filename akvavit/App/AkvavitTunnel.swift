// SPDX-License-Identifier: GPL-3.0-or-later
//
// Starts and stops Akvavit's loopback tunnel (akvavit/Tunnel), which takes the place
// of LocalDevVPN and the Madeira JIT shortcut. JITNetworkShortcut hands over to it
// (patches/): `start` when JIT needs the loopback, `stop` once the debugger has
// detached (restoreBlocking) or JIT failed, `settleAtLaunch` when the app starts.
//
// What works, measured on the iPhone Duo (CLAUDE.md): on Wi-Fi the tunnel reaches
// this iPhone at once. Over cellular data it connects, but the iPhone refuses the
// connection. With no network iOS won't start it, but a tunnel that is already
// running keeps working, in airplane mode too. So by default the tunnel is kept on
// ("Keep the JIT VPN on", with iOS's connect-on-demand, which starts it again
// whenever a network appears, after a restart too), and JIT works offline. Off, it
// runs only while JIT starts.
//
// The first `start` (or setup's "Allow the VPN") saves the VPN configuration, which
// makes iOS ask once. `env.AKVAVIT_TUNNEL = 0` turns the tunnel off, and Madeira's
// own LocalDevVPN and shortcut flow comes back. Log tag: [tunnel].

import Foundation
import Network
// NetworkExtension's managers predate Sendable; their callbacks hand back to the main actor.
@preconcurrency import NetworkExtension

@MainActor final class AkvavitTunnel: ObservableObject {
    static let shared = AkvavitTunnel()

    /// Whether JIT goes through this tunnel rather than LocalDevVPN.
    nonisolated static var enabled: Bool { MadeiraConfig.flag("AKVAVIT_TUNNEL") }
    var handlesJIT: Bool { Self.enabled }

    /// Whether the VPN configuration exists, i.e. iOS has already asked.
    @Published private(set) var installed = false
    /// Whether the tunnel is connected right now.
    @Published private(set) var connected = false

    /// Keep the tunnel running between JIT starts, so JIT also works offline. On by
    /// default; Settings › JIT turns it off (for people who use another VPN app).
    @Published var keepOn = UserDefaults.standard.object(forKey: AkvavitTunnel.keepOnKey) as? Bool ?? true {
        didSet {
            guard keepOn != oldValue else { return }
            UserDefaults.standard.set(keepOn, forKey: Self.keepOnKey)
            log("keep on=\(keepOn ? 1 : 0)")
            guard installed else { return }
            install { [self] _ in
                if keepOn { start { _ in } } else { disconnect() }
            }
        }
    }
    private static let keepOnKey = "akvavitKeepVPNOn"

    nonisolated private static let providerID = (Bundle.main.bundleIdentifier ?? "") + ".Tunnel"
    /// Set while a tunnel this app started for one JIT run is on, so a launch after a
    /// crash can stop it. Not used while the tunnel is kept on.
    private static let runningKey = "akvavitTunnelRunning"
    private var running: Bool {
        get { UserDefaults.standard.bool(forKey: Self.runningKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.runningKey) }
    }
    private var manager: NETunnelProviderManager?
    private var startObserver: NSObjectProtocol?
    private var statusObserver: NSObjectProtocol?

    /// The system's network path, for the messages below.
    nonisolated private static let path: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "akvavit.tunnel.path"))
        return monitor
    }()

    private init() {}

    private func log(_ message: String, level: LogStore.LogEntry.Level = .info) {
        LogStore.shared.log("[tunnel] " + message, level: level)
    }

    // MARK: Messages

    /// What to do when this iPhone can't be reached through the tunnel (Madeira's
    /// "Connect LocalDevVPN" message, when the tunnel handles JIT).
    nonisolated static var unreachableMessage: String {
        // From the interfaces, not the path's own type: with the tunnel up, that can be ours.
        let types = path.currentPath.availableInterfaces.map(\.type)
        if types.contains(.cellular), !types.contains(.wifi) {
            return "This iPhone can't enable JIT while it uses cellular data. Connect to Wi-Fi, or turn on airplane mode for a moment (with Keep the JIT VPN on), then try again. You can turn cellular data back on once the game runs."
        }
        return "Akvavit couldn't reach this iPhone through its VPN. Connect to Wi-Fi, then try again."
    }

    private var noNetworkMessage: String {
        keepOn
            ? "Akvavit's VPN can't start without a network. Connect to Wi-Fi once; after that, with Keep the JIT VPN on, JIT also works offline."
            : "Akvavit's VPN can't start without a network. Connect to Wi-Fi, then try again."
    }

    /// For Settings › JIT.
    var statusText: String {
        !installed ? "Not set up" : connected ? "Connected" : "Not connected"
    }

    // MARK: Configuration

    /// Our saved configuration, if any; also keeps `connected` current.
    private func load(completion: @escaping @MainActor (NETunnelProviderManager?) -> Void) {
        if let manager { completion(manager); return }
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            let found = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerID
            }
            Task { @MainActor in
                if let error { self.log("load failed: \(error.localizedDescription)", level: .error) }
                self.adopt(found)
                completion(found)
            }
        }
    }

    private func adopt(_ found: NETunnelProviderManager?) {
        manager = found
        installed = found != nil
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = nil
        guard let connection = found?.connection else { connected = false; return }
        connected = connection.status == .connected
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.connected = connection.status == .connected }
        }
    }

    /// Learns whether the configuration exists (`installed`) and is connected.
    func refresh() { load { _ in } }

    /// Whether the saved configuration is active and matches `keepOn`.
    private func current(_ m: NETunnelProviderManager) -> Bool {
        m.isEnabled && m.isOnDemandEnabled == keepOn
    }

    /// Saves the configuration (iOS asks the first time), makes it the active VPN and
    /// sets connect-on-demand to match `keepOn`.
    func install(completion: @escaping @MainActor (Error?) -> Void) {
        load { existing in
            let manager = existing ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.providerID
            proto.serverAddress = "This iPhone"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Akvavit"
            manager.isEnabled = true
            // Connect whenever any network is there; with none, iOS can't start a VPN,
            // but one already running stays up.
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
            manager.isOnDemandEnabled = self.keepOn
            manager.saveToPreferences { error in
                // A configuration must be loaded again after saving before it can start.
                manager.loadFromPreferences { loadError in
                    Task { @MainActor in
                        let failure = error ?? loadError
                        if let failure {
                            self.log("install failed: \(failure.localizedDescription)", level: .error)
                        } else {
                            self.adopt(manager)
                            self.log("configuration saved (keep on=\(self.keepOn ? 1 : 0))")
                        }
                        completion(failure)
                    }
                }
            }
        }
    }

    // MARK: Starting and stopping

    /// Connects the tunnel, saving the configuration first when it is missing, not the
    /// active VPN, or its connect-on-demand doesn't match `keepOn` (turning the VPN off
    /// in Settings also turns that off). Calls `completion` once iOS reports it
    /// connected, or with what to do. The caller then waits for LoopbackProbe as it
    /// does for LocalDevVPN.
    func start(timeout: TimeInterval = 10,
               completion: @escaping @MainActor (JITNetworkShortcut.Outcome) -> Void) {
        load { [self] existing in
            if let existing, current(existing) {
                connect(existing, timeout: timeout, completion: completion)
                return
            }
            install { [self] error in
                guard error == nil, let manager else {
                    completion(.failed(error?.localizedDescription ?? "Akvavit's VPN is not set up."))
                    return
                }
                connect(manager, timeout: timeout, completion: completion)
            }
        }
    }

    private func connect(_ manager: NETunnelProviderManager, timeout: TimeInterval,
                         completion: @escaping @MainActor (JITNetworkShortcut.Outcome) -> Void) {
        let connection = manager.connection
        if connection.status == .connected {
            // Only asked to start because the loopback did not answer: with the tunnel
            // already up, waiting won't help (cellular data, typically). Say why now.
            log("connected, but this iPhone did not answer")
            completion(.failed(Self.unreachableMessage))
            return
        }
        // With no network iOS never starts it: say so now instead of after the timeout.
        if Self.path.currentPath.status != .satisfied {
            log("not started: no network")
            completion(.failed(noNetworkMessage))
            return
        }
        var finished = false
        var attempted = false
        let finish: @MainActor (JITNetworkShortcut.Outcome) -> Void = { [self] outcome in
            guard !finished else { return }
            finished = true
            if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
            startObserver = nil
            completion(outcome)
        }
        startObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                switch connection.status {
                case .connecting:
                    attempted = true
                case .connected:
                    self.log("connected")
                    finish(.done(""))
                case .disconnected where attempted, .invalid:
                    // Before "connecting", a disconnected status is only the old state.
                    finish(.failed("Akvavit's VPN did not connect. Try again."))
                default:
                    break
                }
            }
        }
        do {
            if !keepOn { running = true }
            log("starting")
            try connection.startVPNTunnel()
        } catch {
            running = false
            log("start failed: \(error.localizedDescription)", level: .error)
            finish(.failed("Akvavit's VPN did not start: \(error.localizedDescription)"))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(.failed("Akvavit's VPN did not connect within \(Int(timeout)) seconds. Connect to Wi-Fi, then try again."))
        }
    }

    /// After a JIT run: disconnects the tunnel this app started for it. Kept on, the
    /// tunnel stays.
    func stop() {
        guard running, !keepOn else { return }
        running = false
        disconnect()
    }

    private func disconnect() {
        log("stopping")
        load { manager in manager?.connection.stopVPNTunnel() }
    }

    /// At launch. Kept on: make sure connect-on-demand is set, so iOS keeps the tunnel
    /// up. Otherwise a run that ended while the tunnel was on (crash, closed app) left
    /// it connected; turn it off.
    func settleAtLaunch() {
        load { [self] existing in
            if keepOn {
                if let existing, !current(existing) { install { _ in } }
            } else if running {
                log("an earlier run left the tunnel on: stopping it")
                stop()
            }
        }
    }
}
