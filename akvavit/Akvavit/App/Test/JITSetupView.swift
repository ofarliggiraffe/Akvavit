// SPDX-License-Identifier: GPL-3.0-or-later
//
// JIT: set up once (pair, allow the VPN, check), then enable. Deliberately
// plain; it only reads AkvavitKit's JIT model.

import AkvavitKit
import SwiftUI
import UniformTypeIdentifiers

struct JITSetupView: View {
    private let jit = JIT.shared
    @State private var importing = false
    @State private var vpnError: String?
    /// The check ran at least once on this screen, so its result is shown.
    @State private var checked = false

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        Form {
            Section {
                Text("Windows games need JIT. iOS allows it only while a debugger is attached, and Akvavit attaches one itself. That needs this \(device) paired once, and a VPN that only connects to this \(device).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !jit.debuggable {
                Section {
                    Label("This copy of Akvavit isn't signed with a development certificate, so no debugger can attach. Build and install it from Xcode.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            pairingSection
            vpnSection
            checkSection
            enableSection
        }
        .navigationTitle("JIT")
        .onAppear { jit.refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .data]) { result in
            if case .success(let url) = result { jit.importPairingFile(url) }
        }
    }

    private var pairingSection: some View {
        Section {
            if jit.paired {
                Label("Paired", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("Turn on Wi-Fi and tap Start pairing. Then open Settings › Privacy & Security › Developer Mode, tap Pair with \(jit.pairingHostName), and enter the code shown here.")
                switch jit.pairing {
                case .idle:
                    if jit.onDevicePairingSupported {
                        Button("Start pairing") { jit.startPairing() }
                    } else {
                        Text("Pairing on the \(device) itself needs iOS 27. Use a pairing file made on a computer instead.")
                            .foregroundStyle(.secondary)
                    }
                case .waiting:
                    HStack {
                        ProgressView()
                        Text("Waiting for Developer Mode…").foregroundStyle(.secondary)
                    }
                    Button("Cancel", role: .cancel) { jit.cancelPairing() }
                case .code(let code):
                    LabeledContent("Code") {
                        Text(code).font(.title2.monospacedDigit().bold())
                    }
                    Button("Cancel", role: .cancel) { jit.cancelPairing() }
                case .failed(let why):
                    Label(why, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Button("Try again") { jit.startPairing() }
                }
                Button("Use a pairing file instead") { importing = true }
            }
        } header: {
            Text("1. Pair this \(device)")
        }
    }

    private var vpnSection: some View {
        Section {
            if jit.vpnInstalled {
                Label("VPN allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text(jit.usesLocalDevVPN
                     ? "This copy of Akvavit can't run its own VPN (a free Apple ID can't sign it), so JIT goes through LocalDevVPN from the App Store. Get it, allow its VPN when iOS asks, then come back to Akvavit."
                     : "iOS asks once whether Akvavit may add a VPN configuration. It connects only to this \(device), never to the internet.")
                Button("Allow the VPN") {
                    vpnError = nil
                    Task {
                        do { try await jit.installVPN() } catch { vpnError = error.localizedDescription }
                    }
                }
                .disabled(!jit.paired)
                if let vpnError {
                    Label(vpnError, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
            }
        } header: {
            Text("2. Allow the VPN")
        }
    }

    private var checkSection: some View {
        Section {
            Text("Mounts Apple's Developer Disk Image when needed. The first time needs an internet connection.")
            if jit.busy {
                HStack {
                    ProgressView()
                    Text(jit.status ?? "Checking…").foregroundStyle(.secondary)
                }
            } else {
                Button(checked ? "Check again" : "Check setup") {
                    checked = true
                    jit.checkSetup()
                }
                .disabled(!jit.paired || !jit.vpnInstalled)
                if checked {
                    if let error = jit.error {
                        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                    } else {
                        // Not the helper's own message, which names LocalDevVPN (Madeira's helper).
                        Label("Successful", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
        } header: {
            Text("3. Check")
        }
    }

    private var enableSection: some View {
        Section {
            if jit.isOn {
                Label("JIT is on", systemImage: "bolt.fill").foregroundStyle(.green)
            } else {
                Button("Enable JIT") {
                    Task { try? await jit.enable() }
                }
                .disabled(jit.busy || !jit.paired || !jit.vpnInstalled)
            }
            if let error = jit.error, !jit.busy, !checked {
                Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
            }
        }
    }
}
