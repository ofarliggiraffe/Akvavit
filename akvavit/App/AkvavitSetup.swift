// SPDX-License-Identifier: GPL-3.0-or-later
//
// Akvavit's first-run setup, shown instead of Madeira's OnboardingView (patches/).
// It keeps Madeira's setup model (OnboardingModel: which pages, their order, when
// setup opens, finish and skip), and replaces only the pages that change because
// Akvavit enables JIT through its own tunnel (AkvavitTunnel):
//   - welcome: says plainly that this is Madeira;
//   - JIT: pair this iPhone (Madeira's in-app pairing), allow the VPN, check setup;
//   - done.
// Steam sign-in, Valve's client components and Wine Mono are Madeira's own pages:
// for those steps this view shows OnboardingView, which draws the current step.
// With `env.AKVAVIT_TUNNEL = 0`, Madeira's setup is shown unchanged.

import SwiftUI
import UniformTypeIdentifiers

struct AkvavitSetupView: View {
    @ObservedObject private var model = OnboardingModel.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @ObservedObject private var pairing = OnDevicePairing.shared
    @ObservedObject private var tunnel = AkvavitTunnel.shared
    @State private var importingPairingFile = false
    @State private var checkStarted = false
    @State private var checked = false
    @State private var vpnError: String?

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    private var paired: Bool { jit.pairingImported }

    var body: some View {
        switch model.step {
        case .welcome, .done:
            page
        case .jit where tunnel.handlesJIT:
            page
        default:
            OnboardingView()
        }
    }

    private var page: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let position = OnboardingRules.position(of: model.step, in: model.steps), position.count > 1 {
                        Text("Step \(position.number) of \(position.count)")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    switch model.step {
                    case .welcome: welcome
                    case .done: donePage
                    default: jitPage
                    }
                }
                .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                .animation(.default, value: pairing.phase)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        }
        .interactiveDismissDisabled()
        .fileImporter(isPresented: $importingPairingFile, allowedContentTypes: [.propertyList, .data]) { result in
            if case .success(let url) = result {
                jit.importPairingFile(url)
                if jit.pairingImported { jit.method = .builtIn }
            }
        }
        .onAppear {
            jit.refreshPairingStatus()
            tunnel.refresh()
        }
        .onChange(of: jit.busy) { _, busy in
            if checkStarted, !busy {
                checkStarted = false
                checked = jit.error == nil
            }
        }
    }

    // MARK: Building blocks (as Madeira's setup draws them)

    private func header(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.tint).accessibilityHidden(true)
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
        }
    }

    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 36)
        }.buttonStyle(.borderedProminent).controlSize(.large)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).frame(maxWidth: .infinity, minHeight: 44)
    }

    private func point(_ number: Int, _ text: LocalizedStringKey, done: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ZStack {
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.subheadline.weight(.bold))
                }
            }
            .frame(width: 26, height: 26)
            .background((done ? Color.green : Color.accentColor).opacity(0.15), in: Circle()).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(done ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? Text("Done") : Text(""))
    }

    private func problem(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 52)).foregroundStyle(.tint).accessibilityHidden(true)
            Text("Welcome to Madeira").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("Madeira runs Windows games on your \(device).").font(.title3)
            Text("Madeira is made by the [Madeira project](https://github.com/willfaust/Madeira), and all credit for it goes to them. This copy is built by Akvavit, which only packages Madeira so it installs easily and can enable JIT without other apps.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("A few steps get you ready:").foregroundStyle(.secondary)
            let pages = model.steps
            let offered: [LocalizedStringKey] =
                (pages.contains(.jit) ? ["Pair this \(device) and allow a VPN, so Madeira can enable JIT."] : [])
                + (pages.contains(.signIn) ? ["Sign in to Steam in Madeira."] : [])
                + (pages.contains(.dockClient) ? ["Download Valve's Steam client components for Madeira Dock."] : [])
                + (pages.contains(.wineMono) ? ["Download Wine Mono, for games built on .NET Framework."] : [])
            ForEach(offered.indices, id: \.self) { index in point(index + 1, offered[index]) }
            primary("Get started", symbol: "arrow.right") { model.next() }.padding(.top, 8)
            secondary("Skip setup") { model.skip() }
        }
    }

    /// JIT in three steps: pair, allow the VPN, check setup. Each has its own button and
    /// is ticked once done; Continue is always possible.
    private var jitPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Set up JIT", symbol: "bolt.fill")
            Text("Windows games need JIT, which iOS only allows while a debugger is attached. Madeira attaches one itself; it needs to be paired with this \(device) once, and a VPN that only connects to this \(device).")
                .fixedSize(horizontal: false, vertical: true)

            point(1, "**Pair this \(device).** Turn on Wi-Fi and tap **Start pairing**. Then open Settings › Privacy & Security › Developer Mode, scroll down, tap **Pair with \(OnDevicePairing.hostName)** and enter the code shown here.",
                  done: paired)
            if !paired {
                if OnDevicePairing.isSupported {
                    primary("Start pairing", symbol: "dot.radiowaves.left.and.right") { pairing.start() }
                        .disabled(pairing.active)
                    OnDevicePairingPanel()
                } else {
                    Text("Pairing on the \(device) itself needs iOS 27. Use a pairing file made on a computer instead.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                secondary("Use a pairing file instead") { importingPairingFile = true }
            }

            point(2, "**Allow the VPN.** iOS asks once whether Akvavit may add a VPN configuration. It connects only to this \(device), never to the internet. It stays on, so JIT also works offline; if you use another VPN app, turn that off in Settings › JIT.",
                  done: tunnel.installed)
            if paired, !tunnel.installed {
                primary("Allow the VPN", symbol: "lock.shield") {
                    vpnError = nil
                    tunnel.install { error in vpnError = error?.localizedDescription }
                }
                if let vpnError { problem(vpnError) }
            }

            point(3, "**Check setup.** Downloads and mounts Apple's Developer Disk Image when needed. Needs an internet connection the first time.",
                  done: checked)
            if paired, tunnel.installed, !checked {
                if jit.busy {
                    HStack(spacing: 12) { ProgressView(); Text(jit.status ?? "Checking…").foregroundStyle(.secondary) }
                } else {
                    primary(jit.error == nil ? "Check setup" : "Try again", symbol: "checkmark.shield") {
                        jit.method = .builtIn
                        checkStarted = true
                        jit.prepareBuiltIn()
                    }
                    if let error = jit.error { problem(error) }
                }
            }

            if paired, tunnel.installed, checked {
                Label("JIT is ready", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                primary("Continue", symbol: "arrow.right") { model.next() }
            } else {
                secondary("I'll do this later") {
                    if pairing.active { pairing.cancel() }
                    model.next()
                }
            }
        }
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("You're all set", symbol: "checkmark.seal.fill")
            Text("Settings › JIT shows the pairing and the Developer Disk Image, and can pair again.")
            if model.steps.contains(.dockClient) {
                Text("Settings › Steam › Madeira Dock lists the Steam games installed in Madeira's drive_c and starts them.")
            }
            if model.steps.contains(.wineMono) {
                Text("Settings › .NET Framework downloads or removes Wine Mono.")
            }
            Text("You can run this setup again from Settings › JIT or Settings › Steam.").foregroundStyle(.secondary)
            primary("Go to your library", symbol: "square.grid.2x2.fill") { model.finish() }
        }
    }
}
