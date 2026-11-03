// SPDX-License-Identifier: GPL-3.0-or-later
//
// TEMPORARY: runs JITRouteProbe (can the debugger reach this iPhone's
// developer services without the VPN?) and shows its report.

import AkvavitKit
import SwiftUI

struct JITRouteTestView: View {
    @State private var lines: [String] = []
    @State private var running = false
    @State private var keepVPNOn = JITRouteProbe.keepVPNOn
    @State private var vpnConnected = JITRouteProbe.vpnConnected

    var body: some View {
        Form {
            Section {
                Text("Tries to reach this iPhone's developer services at each of its addresses, with or without Akvavit's VPN. Run it once with the VPN on and once with it off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle("Keep the JIT VPN on", isOn: $keepVPNOn)
                    .onChange(of: keepVPNOn) { _, on in JITRouteProbe.keepVPNOn = on }
                LabeledContent("VPN", value: vpnConnected ? "Connected" : "Not connected")
                Button(running ? "Running…" : "Run test") { run() }
                    .disabled(running)
            }
            if !lines.isEmpty {
                Section("Result") {
                    Text(lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("JIT route test")
        .task {
            // The VPN's state changes a moment after the switch.
            while !Task.isCancelled {
                JITRouteProbe.refreshVPN()
                vpnConnected = JITRouteProbe.vpnConnected
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func run() {
        running = true
        lines = []
        Task {
            _ = await JITRouteProbe.run { line in
                Task { @MainActor in lines.append(line) }
            }
            running = false
        }
    }
}
