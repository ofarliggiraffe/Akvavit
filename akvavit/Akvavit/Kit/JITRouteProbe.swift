// SPDX-License-Identifier: GPL-3.0-or-later
//
// TEMPORARY experiment: can the debugger reach this iPhone's developer
// services without a VPN? Lists the iPhone's addresses and what it advertises
// on Bonjour, tries a TCP connection to the remote-pairing port (49152, the
// one StikJIT uses) and lockdownd (62078) at every address, asks lockdownd
// for its type where it answers, and where the remote-pairing port opens,
// tries the whole route: Madeira's tunnel code (madeira_rppairing_install_profile:
// pairing, encrypted tunnel, service discovery, misagent) reinstalling this
// app's own provisioning profile, which changes nothing on the device.
// Log tag: [jit-probe] (no device names, identifiers or TXT values).

import Darwin
import dnssd
import Foundation
import Network

public enum JITRouteProbe {
    public static let remotePairingPort: UInt16 = 49152
    public static let lockdownPort: UInt16 = 62078
    static let browsedTypes = ["_remotepairing._tcp", "_apple-mobdev2._tcp"]

    /// Akvavit's VPN is connected.
    @MainActor public static var vpnConnected: Bool { AkvavitTunnel.shared.connected }
    /// The "Keep the JIT VPN on" setting: on starts the VPN, off disconnects it.
    @MainActor public static var keepVPNOn: Bool {
        get { AkvavitTunnel.shared.keepOn }
        set { AkvavitTunnel.shared.keepOn = newValue }
    }
    @MainActor public static func refreshVPN() { AkvavitTunnel.shared.refresh() }

    /// Runs every step and returns the report, line by line. `progress` gets
    /// each line as it is made.
    public static func run(progress: @escaping @Sendable (String) -> Void) async -> [String] {
        let report = Report(progress: progress)
        let vpn = await MainActor.run { AkvavitTunnel.shared.connected }
        report.add("Akvavit's VPN: \(vpn ? "connected" : "not connected")")
        let path = await NWPathMonitorSnapshot.current()
        report.add("Main network: \(path)")

        // 1. The iPhone's own addresses.
        report.add("")
        report.add("This iPhone's addresses:")
        let interfaces = Interface.all()
        for i in interfaces { report.add("  \(i.name)  \(i.address)") }
        if interfaces.isEmpty { report.add("  (none)") }

        // 2. What it advertises.
        report.add("")
        report.add("Advertised on Bonjour (3 s):")
        let services = await Bonjour.browse(types: browsedTypes, seconds: 3)
        for s in services {
            report.add("  \(s.type) on \(s.interface): \(s.name), host \(s.host), port \(s.port)",
                       log: "  \(s.type) on \(s.interface): port \(s.port), \(s.addresses.count) address(es)")
            for a in s.addresses { report.add("      \(a)") }
        }
        if services.isEmpty { report.add("  (nothing)") }

        // 3. TCP to every address.
        var targets: [String] = ["127.0.0.1", "::1", "10.7.0.1"]
        for i in interfaces where !targets.contains(i.address) { targets.append(i.address) }
        for s in services { for a in s.addresses where !targets.contains(a) { targets.append(a) } }
        var ports: [UInt16] = [remotePairingPort, lockdownPort]
        for s in services where !ports.contains(s.port) { ports.append(s.port) }

        report.add("")
        report.add("TCP connections (1.5 s each):")
        var open: [(String, UInt16)] = []
        let results = await withTaskGroup(of: (Int, String, UInt16, String).self) { group in
            var index = 0
            for t in targets { for p in ports {
                let n = index; index += 1
                group.addTask { (n, t, p, TCP.probe(host: t, port: p, timeout: 1.5).text) }
            } }
            var all: [(Int, String, UInt16, String)] = []
            for await r in group { all.append(r) }
            return all.sorted { $0.0 < $1.0 }
        }
        for (_, t, p, text) in results {
            report.add("  \(t) : \(p)  \(text)")
            if text == "open" { open.append((t, p)) }
        }

        // 4. lockdownd's answer where its port opened.
        for (t, p) in open where p == lockdownPort {
            report.add("")
            report.add("lockdownd at \(t): \(Lockdown.queryType(host: t, port: p))")
        }

        // 5. The whole route where a remote-pairing port opened.
        let pairing = try? JITPairingFileStore.data()
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        let routes = open.filter { $0.1 != lockdownPort && !$0.0.contains("%") }
        if !routes.isEmpty {
            report.add("")
            report.add("Whole route (pairing, tunnel, services), 10 s each:")
            if pairing == nil { report.add("  skipped: no pairing file") }
            if profile == nil { report.add("  skipped: this app has no embedded provisioning profile") }
            if let pairing, let profile {
                for (t, p) in routes {
                    report.add("  \(t) : \(p)  \(Route.tryInstall(pairing: pairing, profile: profile, host: t, port: p))")
                }
            }
        }
        report.add("")
        report.add("Done.")
        return report.lines
    }

    // MARK: - The main network

    enum NWPathMonitorSnapshot {
        /// The system's network path: its interfaces in order of preference.
        static func current() async -> String {
            await withCheckedContinuation { done in
                let monitor = NWPathMonitor()
                let once = Once()
                monitor.pathUpdateHandler = { path in
                    guard once.first() else { return }
                    monitor.cancel()
                    let names = path.availableInterfaces.map { "\($0.name) (\(describe($0.type)))" }
                    done.resume(returning: "\(path.status == .satisfied ? "up" : "down"), interfaces " +
                                (names.isEmpty ? "none" : names.joined(separator: ", ")))
                }
                monitor.start(queue: DispatchQueue(label: "akvavit.jit-probe.path"))
            }
        }

        private static func describe(_ type: NWInterface.InterfaceType) -> String {
            switch type {
            case .wifi: return "Wi-Fi"
            case .cellular: return "cellular"
            case .wiredEthernet: return "wired"
            case .loopback: return "loopback"
            case .other: return "other"
            @unknown default: return "?"
            }
        }

        private final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
    }

    // MARK: - Report

    private final class Report: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var lines: [String] = []
        let progress: @Sendable (String) -> Void
        init(progress: @escaping @Sendable (String) -> Void) { self.progress = progress }

        /// `log` replaces the line in the log file (no device names there).
        func add(_ line: String, log: String? = nil) {
            lock.lock(); lines.append(line); lock.unlock()
            progress(line)
            let text = log ?? line
            if !text.isEmpty { LogStore.shared.log("[jit-probe] " + text) }
        }
    }

    // MARK: - Interfaces

    struct Interface {
        let name: String
        let address: String

        static func all() -> [Interface] {
            var list: [Interface] = []
            var head: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&head) == 0, let first = head else { return [] }
            defer { freeifaddrs(head) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let entry = cursor {
                defer { cursor = entry.pointee.ifa_next }
                guard let sa = entry.pointee.ifa_addr,
                      sa.pointee.sa_family == AF_INET || sa.pointee.sa_family == AF_INET6,
                      entry.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
                let name = String(cString: entry.pointee.ifa_name)
                if let text = numericHost(sa) { list.append(Interface(name: name, address: text)) }
            }
            return list
        }
    }

    static func numericHost(_ sa: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(sa.pointee.sa_family == AF_INET6 ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(sa, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Bonjour

    struct Service {
        let type: String
        let name: String
        let interface: String
        var host = "?"
        var port: UInt16 = 0
        var addresses: [String] = []
    }

    /// Browses `types` for `seconds`, resolving each service found and looking
    /// up its host's addresses on the interface it was found on.
    enum Bonjour {
        static func browse(types: [String], seconds: Double) async -> [Service] {
            await withCheckedContinuation { done in
                let browser = Browser()
                browser.start(types: types)
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    done.resume(returning: browser.stop())
                }
            }
        }
    }

    private final class Browser: @unchecked Sendable {
        let queue = DispatchQueue(label: "akvavit.jit-probe.bonjour")
        var refs: [DNSServiceRef] = []
        var services: [Service] = []

        func start(types: [String]) {
            queue.sync {
                for type in types {
                    var ref: DNSServiceRef?
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    let error = DNSServiceBrowse(&ref, 0, 0, type, nil, { _, flags, interface, error, name, type, domain, context in
                        guard error == kDNSServiceErr_NoError, flags & kDNSServiceFlagsAdd != 0,
                              let context, let name, let type, let domain else { return }
                        let browser = Unmanaged<Browser>.fromOpaque(context).takeUnretainedValue()
                        browser.found(name: String(cString: name), type: String(cString: type),
                                      domain: String(cString: domain), interface: interface)
                    }, context)
                    if error == kDNSServiceErr_NoError, let ref {
                        DNSServiceSetDispatchQueue(ref, queue)
                        refs.append(ref)
                    } else {
                        LogStore.shared.log("[jit-probe] browse \(type) failed: \(error)")
                    }
                }
            }
        }

        func stop() -> [Service] {
            queue.sync {
                for ref in refs { DNSServiceRefDeallocate(ref) }
                refs.removeAll()
                return services
            }
        }

        /// Called on `queue`.
        private func found(name: String, type: String, domain: String, interface: UInt32) {
            var ifname = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
            let interfaceName = if_indextoname(interface, &ifname) != nil ? String(cString: ifname) : "#\(interface)"
            let index = services.count
            services.append(Service(type: type.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                                    name: name, interface: interfaceName))
            let box = Unmanaged.passRetained(ResolveContext(browser: self, index: index)).toOpaque()
            var ref: DNSServiceRef?
            let error = DNSServiceResolve(&ref, 0, interface, name, type, domain, { _, _, interface, error, _, host, port, _, _, context in
                guard let context else { return }
                let ctx = Unmanaged<ResolveContext>.fromOpaque(context).takeUnretainedValue()
                guard error == kDNSServiceErr_NoError, let host else { return }
                ctx.browser.resolved(index: ctx.index, host: String(cString: host),
                                     port: UInt16(bigEndian: port), interface: interface)
            }, box)
            if error == kDNSServiceErr_NoError, let ref {
                DNSServiceSetDispatchQueue(ref, queue)
                refs.append(ref)
            }
        }

        /// Called on `queue`.
        func resolved(index: Int, host: String, port: UInt16, interface: UInt32) {
            guard services.indices.contains(index) else { return }
            services[index].host = host
            services[index].port = port
            let box = Unmanaged.passRetained(ResolveContext(browser: self, index: index)).toOpaque()
            var ref: DNSServiceRef?
            let protocols = DNSServiceProtocol(kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6)
            let error = DNSServiceGetAddrInfo(&ref, 0, interface, protocols, host, { _, _, _, error, _, address, _, context in
                guard let context else { return }
                let ctx = Unmanaged<ResolveContext>.fromOpaque(context).takeUnretainedValue()
                guard error == kDNSServiceErr_NoError, let address,
                      let text = JITRouteProbe.numericHost(address) else { return }
                ctx.browser.addAddress(index: ctx.index, text)
            }, box)
            if error == kDNSServiceErr_NoError, let ref {
                DNSServiceSetDispatchQueue(ref, queue)
                refs.append(ref)
            }
        }

        /// Called on `queue`.
        func addAddress(index: Int, _ text: String) {
            guard services.indices.contains(index), !services[index].addresses.contains(text) else { return }
            services[index].addresses.append(text)
        }
    }

    /// Kept for the run (a few objects); the callbacks may fire until stop().
    private final class ResolveContext {
        let browser: Browser
        let index: Int
        init(browser: Browser, index: Int) { self.browser = browser; self.index = index }
    }

    // MARK: - TCP

    enum TCP {
        enum Outcome {
            case open, refused, timeout, failed(String)
            var text: String {
                switch self {
                case .open: return "open"
                case .refused: return "refused"
                case .timeout: return "no answer"
                case .failed(let why): return why
                }
            }
        }

        static func probe(host: String, port: UInt16, timeout: Double) -> Outcome {
            var result: Outcome = .failed("failed")
            guard let fd = connect(host: host, port: port, timeout: timeout, outcome: { result = $0 }) else {
                return result
            }
            close(fd)
            return .open
        }

        /// A connected socket, or nil (`outcome` says why).
        static func connect(host: String, port: UInt16, timeout: Double,
                            outcome: (Outcome) -> Void) -> Int32? {
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST
            hints.ai_socktype = SOCK_STREAM
            var info: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
                outcome(.failed("not an address")); return nil
            }
            defer { freeaddrinfo(info) }
            let fd = socket(first.pointee.ai_family, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { outcome(.failed("socket: \(String(cString: strerror(errno)))")); return nil }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            if Darwin.connect(fd, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0 {
                _ = fcntl(fd, F_SETFL, flags)
                return fd
            }
            guard errno == EINPROGRESS else {
                let e = errno
                close(fd)
                outcome(e == ECONNREFUSED ? .refused : .failed(String(cString: strerror(e))))
                return nil
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&pfd, 1, Int32(timeout * 1000))
            if ready <= 0 { close(fd); outcome(.timeout); return nil }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
            if error != 0 {
                close(fd)
                outcome(error == ECONNREFUSED ? .refused : .failed(String(cString: strerror(error))))
                return nil
            }
            _ = fcntl(fd, F_SETFL, flags)
            return fd
        }
    }

    // MARK: - lockdownd

    enum Lockdown {
        /// Sends lockdownd's QueryType request (a length-prefixed XML plist)
        /// and returns what it answered.
        static func queryType(host: String, port: UInt16) -> String {
            guard let fd = TCP.connect(host: host, port: port, timeout: 1.5, outcome: { _ in }) else {
                return "could not connect again"
            }
            defer { close(fd) }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            guard let body = try? PropertyListSerialization.data(
                fromPropertyList: ["Label": "Akvavit", "Request": "QueryType"], format: .xml, options: 0) else {
                return "could not make the request"
            }
            var length = UInt32(body.count).bigEndian
            var packet = Data(bytes: &length, count: 4)
            packet.append(body)
            let sent = packet.withUnsafeBytes { send(fd, $0.baseAddress, packet.count, 0) }
            guard sent == packet.count else { return "send failed: \(String(cString: strerror(errno)))" }
            guard let header = read(fd, count: 4) else { return "no answer (\(String(cString: strerror(errno))))" }
            let size = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard size > 0, size < 1 << 20, let reply = read(fd, count: size) else { return "answer cut short" }
            guard let plist = try? PropertyListSerialization.propertyList(from: reply, format: nil) as? [String: Any] else {
                return "answered \(size) bytes, not a plist"
            }
            if let type = plist["Type"] as? String { return "answered, Type = \(type)" }
            if let error = plist["Error"] as? String { return "answered with error \(error)" }
            return "answered with keys \(plist.keys.sorted().joined(separator: ", "))"
        }

        private static func read(_ fd: Int32, count: Int) -> Data? {
            var data = Data(count: count)
            var got = 0
            while got < count {
                let n = data.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, count - got, 0) }
                if n <= 0 { return nil }
                got += n
            }
            return data
        }
    }

    // MARK: - The whole route

    enum Route {
        static func tryInstall(pairing: Data, profile: Data, host: String, port: UInt16) -> String {
            var error: UnsafeMutablePointer<CChar>?
            let code = pairing.withUnsafeBytes { p in
                profile.withUnsafeBytes { q in
                    madeira_rppairing_install_profile(
                        p.bindMemory(to: UInt8.self).baseAddress, pairing.count, host, port,
                        q.bindMemory(to: UInt8.self).baseAddress, profile.count, 10, &error)
                }
            }
            var message = ""
            if let error {
                message = String(cString: error)
                madeira_rppairing_string_free(error)
            }
            switch code {
            case 0: return "WORKS: tunnel and developer services reached"
            case 1: return "not reached: \(message)"
            case 2: return "reached, pairing refused: \(message)"
            default: return "failed: \(message)"
            }
        }
    }
}
