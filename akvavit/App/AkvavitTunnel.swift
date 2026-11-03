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
//
// Our tunnel needs the Network Extensions capability, which only a paid developer
// account gives. Without it (a free Apple ID, or a sideloader that dropped it), the
// same calls drive LocalDevVPN from the App Store instead (our own code, from
// LocalDevVPN's URL handler): `localdevvpn://enable` starts its VPN, and with
// `?scheme=akvavit` it opens Akvavit again a second later. Its VPN connects on
// demand for 10.7.0.1 from then on. The first time, iOS asks inside LocalDevVPN
// whether its VPN may be added, so that first connect doesn't ask it to come back.
// `env.AKVAVIT_OWN_VPN = 0` picks LocalDevVPN for testing.

import Foundation
import Network
import Security
import UIKit
// NetworkExtension's managers predate Sendable; their callbacks hand back to the main actor.
@preconcurrency import NetworkExtension

@MainActor final class AkvavitTunnel: ObservableObject {
    static let shared = AkvavitTunnel()

    /// Whether JIT goes through this tunnel rather than LocalDevVPN.
    nonisolated static var enabled: Bool { MadeiraConfig.flag("AKVAVIT_TUNNEL") }
    var handlesJIT: Bool { Self.enabled }

    enum Backend { case own, localDevVPN }
    /// Which VPN carries JIT's connection: ours when the app may run it.
    nonisolated static let backend: Backend = {
        let own = MadeiraConfig.flag("AKVAVIT_OWN_VPN") && hasTunnelCapability
        LogStore.shared.log("[tunnel] VPN: \(own ? "Akvavit's own" : "LocalDevVPN")"
                            + (hasTunnelCapability ? "" : " (no Network Extensions capability)"))
        return own ? .own : .localDevVPN
    }()
    nonisolated static var usesLocalDevVPN: Bool { backend == .localDevVPN }

    /// Whether the VPN configuration exists, i.e. iOS has already asked.
    @Published private(set) var installed = false
    /// Whether the tunnel is connected right now.
    @Published private(set) var connected = false

    /// Keep the tunnel running between JIT starts, so JIT also works offline. On by
    /// default; Settings › JIT turns it off (for people who use another VPN app).
    /// LocalDevVPN keeps itself on (connect-on-demand).
    @Published var keepOn = UserDefaults.standard.object(forKey: AkvavitTunnel.keepOnKey) as? Bool ?? true {
        didSet {
            guard keepOn != oldValue, !Self.usesLocalDevVPN else { return }
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
            return usesLocalDevVPN
                ? "This iPhone can't enable JIT while it uses cellular data. Connect to Wi-Fi, or turn on airplane mode for a moment, then try again. You can turn cellular data back on once the game runs."
                : "This iPhone can't enable JIT while it uses cellular data. Connect to Wi-Fi, or turn on airplane mode for a moment (with Keep the JIT VPN on), then try again. You can turn cellular data back on once the game runs."
        }
        return usesLocalDevVPN
            ? "Akvavit couldn't reach this iPhone through LocalDevVPN. Connect to Wi-Fi, then try again."
            : "Akvavit couldn't reach this iPhone through its VPN. Connect to Wi-Fi, then try again."
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
    func refresh() {
        if Self.usesLocalDevVPN { refreshLocalDevVPN(); return }
        load { _ in }
    }

    /// Whether the saved configuration is active and matches `keepOn`.
    private func current(_ m: NETunnelProviderManager) -> Bool {
        m.isEnabled && m.isOnDemandEnabled == keepOn
    }

    /// Saves the configuration (iOS asks the first time), makes it the active VPN and
    /// sets connect-on-demand to match `keepOn`.
    func install(completion: @escaping @MainActor (Error?) -> Void) {
        if Self.usesLocalDevVPN { installLocalDevVPN(completion: completion); return }
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
        if Self.usesLocalDevVPN { startLocalDevVPN(completion: completion); return }
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
        guard !Self.usesLocalDevVPN, running, !keepOn else { return }
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
        if Self.usesLocalDevVPN { refreshLocalDevVPN(); return }
        load { [self] existing in
            if keepOn {
                if let existing, !current(existing) { install { _ in } }
            } else if running {
                log("an earlier run left the tunnel on: stopping it")
                stop()
            }
        }
    }

    // MARK: LocalDevVPN

    nonisolated static let localDevVPNAppStore = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!
    /// Set once LocalDevVPN's VPN has been seen connected: iOS has allowed it, so later
    /// connects may ask LocalDevVPN to come straight back.
    private static let localDevVPNAllowedKey = "akvavitLocalDevVPNAllowed"
    private var localDevVPNAllowed: Bool {
        get { UserDefaults.standard.bool(forKey: Self.localDevVPNAllowedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.localDevVPNAllowedKey) }
    }

    static var localDevVPNInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "localdevvpn://")!)
    }

    /// LocalDevVPN's tunnel is up: an interface with an address in its 10.7.0.0/16.
    nonisolated static var localDevVPNUp: Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == AF_INET,
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  String(cString: entry.pointee.ifa_name).hasPrefix("utun") else { continue }
            let address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            if bytes[0] == 10, bytes[1] == 7 { return true }
        }
        return false
    }

    private func refreshLocalDevVPN() {
        let up = Self.localDevVPNUp
        if up, !localDevVPNAllowed { localDevVPNAllowed = true }
        installed = Self.localDevVPNInstalled && localDevVPNAllowed
        connected = up
    }

    /// Setup's LocalDevVPN page: its App Store page.
    func openLocalDevVPNAppStore() {
        log("LocalDevVPN: opening the App Store")
        UIApplication.shared.open(Self.localDevVPNAppStore)
    }

    /// Setup's LocalDevVPN page: opens LocalDevVPN, which connects. The first time
    /// iOS asks there, so it stays; once its VPN has been allowed, it comes back.
    func openLocalDevVPN() {
        let allowed = localDevVPNAllowed
        log("LocalDevVPN: connecting from setup\(allowed ? "" : " (first time: iOS asks there)")")
        UIApplication.shared.open(URL(string: allowed ? "localdevvpn://enable?scheme=akvavit" : "localdevvpn://enable")!)
    }

    /// Setup's VPN step: gets LocalDevVPN from the App Store when it is missing, then
    /// connects it once, so iOS asks there. Done when its tunnel is up.
    private func installLocalDevVPN(completion: @escaping @MainActor (Error?) -> Void) {
        refreshLocalDevVPN()
        if installed { completion(nil); return }
        let fail: (String) -> Error = { NSError(domain: "AkvavitTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: $0]) }
        Task { @MainActor in
            if !Self.localDevVPNInstalled {
                log("LocalDevVPN missing: opening the App Store")
                _ = await UIApplication.shared.open(Self.localDevVPNAppStore)
                guard await waitFor(seconds: 600, { Self.localDevVPNInstalled }) else {
                    completion(fail("LocalDevVPN isn't installed. Get it from the App Store, then try again."))
                    return
                }
            }
            log("LocalDevVPN: first connect (iOS asks there)")
            _ = await UIApplication.shared.open(URL(string: "localdevvpn://enable")!)
            guard await waitFor(seconds: 300, { Self.localDevVPNUp }) else {
                completion(fail("LocalDevVPN didn't connect. Open LocalDevVPN, allow its VPN and connect it, then come back to Akvavit."))
                return
            }
            log("LocalDevVPN connected")
            refreshLocalDevVPN()
            completion(nil)
        }
    }

    /// JIT needs the loopback: connects LocalDevVPN (it opens Akvavit again a second
    /// later) and waits for its tunnel.
    private func startLocalDevVPN(completion: @escaping @MainActor (JITNetworkShortcut.Outcome) -> Void) {
        refreshLocalDevVPN()
        if connected {
            log("LocalDevVPN connected, but this iPhone did not answer")
            completion(.failed(Self.unreachableMessage))
            return
        }
        guard Self.localDevVPNInstalled else {
            completion(.failed("JIT needs LocalDevVPN. Get it from the App Store, then try again."))
            return
        }
        if Self.path.currentPath.status != .satisfied {
            log("LocalDevVPN not started: no network")
            completion(.failed("LocalDevVPN can't start without a network. Connect to Wi-Fi, then try again."))
            return
        }
        let allowed = localDevVPNAllowed
        Task { @MainActor in
            log("connecting LocalDevVPN\(allowed ? "" : " (first time: iOS asks there)")")
            let link = allowed ? "localdevvpn://enable?scheme=akvavit" : "localdevvpn://enable"
            _ = await UIApplication.shared.open(URL(string: link)!)
            guard await waitFor(seconds: allowed ? 20 : 300, { Self.localDevVPNUp }) else {
                completion(.failed("LocalDevVPN didn't connect. Open LocalDevVPN and connect it, then come back to Akvavit and try again."))
                return
            }
            log("LocalDevVPN connected")
            refreshLocalDevVPN()
            completion(.done(""))
        }
    }

    /// Checks `condition` every 0.3 s until it holds (true) or `seconds` pass (false).
    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return condition()
    }

    // MARK: The capability

    /// The app is signed with Network Extensions' packet tunnel, which our tunnel needs.
    nonisolated static let hasTunnelCapability: Bool = {
        guard let task = SecTaskCreateFromSelfForTunnel(nil),
              let value = SecTaskCopyValueForEntitlementForTunnel(
                  task, "com.apple.developer.networking.networkextension" as NSString, nil) else { return false }
        return (value as? [String])?.contains("packet-tunnel-provider") ?? false
    }()
}

// Security's task calls, public in macOS's SDK but not in iOS's headers.
@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelfForTunnel(_ allocator: CFAllocator?) -> OpaquePointer?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlementForTunnel(
    _ task: OpaquePointer, _ entitlement: NSString, _ error: NSErrorPointer) -> CFTypeRef?
