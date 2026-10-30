// SPDX-License-Identifier: GPL-3.0-or-later
//
// Settings › JIT when Akvavit's own tunnel handles JIT (shown instead of Madeira's
// JITSettingsSection, patches/): JIT setup, run setup again, and whether the JIT VPN
// is kept on (AkvavitTunnel). Madeira's method picker and its LocalDevVPN shortcut
// don't apply here.

import SwiftUI

struct AkvavitJITSettingsSection: View {
    @ObservedObject private var tunnel = AkvavitTunnel.shared
    @ObservedObject private var coordinator = JITCoordinator.shared
    @ObservedObject private var onboarding = OnboardingModel.shared

    var body: some View {
        Section {
            Button {
                coordinator.showSetup = true
            } label: {
                Label("JIT setup", systemImage: "bolt.badge.clock")
            }
            if onboarding.available {
                Button {
                    onboarding.rerun()
                } label: {
                    Label("Run setup again", systemImage: "wand.and.stars")
                }
            }
            Toggle("Keep the JIT VPN on", isOn: $tunnel.keepOn)
            LabeledContent("JIT VPN", value: tunnel.statusText)
        } header: {
            Text("JIT")
        } footer: {
            Text("Akvavit enables JIT through a VPN that only connects to this iPhone; your internet traffic doesn't use it. Kept on, JIT also works without a network, for example in airplane mode. Off, the VPN runs only while JIT starts, which needs Wi-Fi. iOS runs one VPN at a time, so turn this off if you use another VPN app. JIT can't start while the iPhone uses cellular data: use Wi-Fi, or turn on airplane mode for a moment.")
        }
        .onAppear { tunnel.refresh() }
    }
}
