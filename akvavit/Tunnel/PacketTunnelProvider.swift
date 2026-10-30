// SPDX-License-Identifier: GPL-3.0-or-later
//
// Akvavit's loopback tunnel: lets StikJIT reach this iPhone's own lockdownd, so
// JIT needs no other app (it replaces LocalDevVPN).
//
// The tunnel interface gets 10.7.0.2 and routes only 10.7.0.1. A connection to
// 10.7.0.1:62078 leaves as a packet from 10.7.0.2 to 10.7.0.1; swapping its two
// addresses turns it into one from 10.7.0.1 to 10.7.0.2, which the system takes
// as arriving at its own tunnel address, so lockdownd answers. Its replies come
// back through the tunnel and are swapped the same way. Swapping changes no
// checksum: the IPv4 header checksum and the TCP/UDP pseudo-header sums add both
// addresses, so their order doesn't matter.
//
// The addresses match LocalDevVPN's (10.7.0.0/16), so Madeira's LoopbackProbe and
// StikJIT's default device address work unchanged.

import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    static let interfaceAddress = "10.7.0.2"
    static let deviceAddress = "10.7.0.1"

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // There is no server: the remote address only names the tunnel.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: [Self.interfaceAddress], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: Self.deviceAddress,
                                           subnetMask: "255.255.255.255")]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        setTunnelNetworkSettings(settings) { [weak self] error in
            completionHandler(error)
            if error == nil { self?.forward() }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    /// Sends every packet back with its addresses swapped, for as long as the tunnel runs.
    private func forward() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var out: [Data] = []
            var outProtocols: [NSNumber] = []
            for (packet, proto) in zip(packets, protocols) {
                guard let swapped = Self.swapAddresses(packet) else { continue }
                out.append(swapped)
                outProtocols.append(proto)
            }
            if !out.isEmpty { packetFlow.writePackets(out, withProtocols: outProtocols) }
            forward()
        }
    }

    /// The IPv4 packet with its source and destination addresses swapped; nil for
    /// anything else, which is dropped.
    static func swapAddresses(_ packet: Data) -> Data? {
        var bytes = [UInt8](packet)
        guard bytes.count >= 20, bytes[0] >> 4 == 4 else { return nil }
        for i in 12..<16 { bytes.swapAt(i, i + 4) }
        return Data(bytes)
    }
}
