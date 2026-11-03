// SPDX-License-Identifier: GPL-3.0-or-later
//
// Setup, on first start (and from Settings › Run setup again): a card over
// the blurred home screen whose steps slide under dots that stay put.
// Welcome, LocalDevVPN (only when this copy can't run Akvavit's own VPN),
// JIT (pairing, VPN and check run as one chain), Steam, done.

import AkvavitKit
import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    private let flow = SetupFlow.shared
    @State private var step = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let blue = AppTab.home.colors.tint
    private static let teal = AppTab.getGames.colors.tint

    private enum Page { case welcome, localDevVPN, jit, steam, done }
    private let pages: [Page] = JIT.shared.usesLocalDevVPN
        ? [.welcome, .localDevVPN, .jit, .steam, .done]
        : [.welcome, .jit, .steam, .done]

    private func color(_ page: Page) -> Color {
        switch page {
        case .welcome, .steam: return Self.blue
        case .localDevVPN, .jit: return Self.teal
        case .done: return Theme.success
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 640
            let width = wide ? 600 : min(proxy.size.width - 28, 520)
            let height = wide ? min(452, proxy.size.height - 32) : min(proxy.size.height - 48, 600)
            ZStack {
                // Setup can't be dismissed by tapping outside; this only takes the taps.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Theme.dim)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture {}
                    .accessibilityHidden(true)
                card(width: width, height: height, wide: wide)
                    .scaleEffect(shown ? 1 : 0.94)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { shown = true }
        }
    }

    private func card(width: CGFloat, height: CGFloat, wide: Bool) -> some View {
        let layout = SetupLayout(wide: wide, height: height)
        return ZStack(alignment: .bottom) {
            if reduceMotion {
                page(step, layout: layout)
                    .frame(width: width, height: height)
                    .id(step)
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        page(index, layout: layout)
                            .frame(width: width, height: height)
                            .accessibilityHidden(index != step)
                            .allowsHitTesting(index == step)
                    }
                }
                .frame(width: width, alignment: .leading)
                .offset(x: -CGFloat(step) * width)
            }
            dots
                .padding(.bottom, layout.wide ? 26 : 20)
        }
        .frame(width: width, height: height)
        .clipped()
        .background(Theme.card, in: .rect(cornerRadius: 28))
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: Theme.shadow.opacity(0.35), radius: 40, y: 30)
        .foregroundStyle(Theme.cardText)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == step ? color(pages[step])
                          : Theme.cardText.opacity(index < step ? 0.35 : 0.14))
                    .frame(width: index == step ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(pages.count)")
    }

    private func go(to next: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3)
                      : GamePopupModel.flip(duration: 0.52)) {
            step = next
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.4)) {
            shown = false
        } completion: {
            flow.finish()
        }
    }

    @ViewBuilder
    private func page(_ index: Int, layout: SetupLayout) -> some View {
        let next = { go(to: index + 1) }
        switch pages[index] {
        case .welcome:
            SetupPage(layout: layout, color: Self.blue, symbol: "sparkles", title: "Welcome to Akvavit",
                      text: "Akvavit runs Windows games on your iPhone with Madeira’s engine: FEX-Emu, Wine and DXMT, ported to iOS by the Madeira project. \(pages.count == 5 ? "Three" : "Two") short steps get you ready.") {
                EmptyView()
            } primary: {
                Button("Get started") { next() }
                    .buttonStyle(FilledButtonStyle(color: Self.blue, height: 56, fontSize: 19))
            } secondary: {
                EmptyView()
            }
        case .localDevVPN:
            LocalDevVPNStep(layout: layout, color: Self.teal, next: next)
        case .jit:
            JITStep(layout: layout, color: Self.teal, next: next)
        case .steam:
            SteamSignInStep(layout: layout, color: Self.blue, later: next, next: next)
        case .done:
            SetupPage(layout: layout, color: Theme.success, symbol: "checkmark", title: "You’re all set",
                      text: "Pick a game in Get games to install it. You can run setup again from Settings.") {
                EmptyView()
            } primary: {
                Button("Go to your library") { close() }
                    .buttonStyle(FilledButtonStyle(color: Theme.success, height: 56, fontSize: 19))
            } secondary: {
                EmptyView()
            }
        }
    }
}

/// Sizes for the card: the inner display, the outer one, and a short card
/// (landscape on the outer display, or with the keyboard up).
struct SetupLayout {
    let wide: Bool
    let height: CGFloat

    var showsIcon: Bool { height >= 400 }
    var showsText: Bool { height >= 300 }
    var horizontalPadding: CGFloat { wide ? 40 : 26 }
    var topPadding: CGFloat { height >= 400 ? (wide ? 34 : 28) : 20 }
    var titleSize: CGFloat { wide ? 28 : 26 }
}

/// One step: icon, title, text, the step's own content, then its buttons.
/// The sign-in cards over Get games use it too.
struct SetupPage<Middle: View, Primary: View, Secondary: View>: View {
    let layout: SetupLayout
    let color: Color
    let symbol: String
    /// A store logo (template image) in place of the symbol.
    var logo: String? = nil
    let title: String
    let text: String
    @ViewBuilder let middle: Middle
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if layout.showsIcon {
                Group {
                    if let logo {
                        Image(logo).resizable().renderingMode(.template).scaledToFit().frame(width: 34, height: 34)
                    } else {
                        Image(systemName: symbol).font(.system(size: 28, weight: .semibold))
                    }
                }
                    .foregroundStyle(color)
                    .frame(width: 64, height: 64)
                    .background(color.opacity(0.14), in: .rect(cornerRadius: 20))
                    .accessibilityHidden(true)
                    .padding(.bottom, 20)
            }
            Text(title)
                .font(.quicksand(layout.titleSize, .bold, relativeTo: .title))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)
            if layout.showsText {
                Text(text)
                    .font(.quicksand(layout.wide ? 16 : 15, .semibold, relativeTo: .body))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.cardSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            middle
                .padding(.top, 16)
            Spacer(minLength: 12)
            primary
            secondary
                .buttonStyle(LinkButtonStyle())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.top, layout.topPadding)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.wide ? 44 : 38)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(15, .bold, relativeTo: .body))
            .foregroundStyle(Theme.link)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - JIT

private struct JITStep: View {
    let layout: SetupLayout
    let color: Color
    let next: () -> Void
    private let flow = SetupFlow.shared
    private let jit = JIT.shared
    @State private var importing = false

    var body: some View {
        SetupPage(layout: layout, color: color, symbol: "bolt.fill", title: "Set up JIT",
                  text: "Games need JIT. Turn on Wi-Fi and tap Start pairing, then open Settings › Privacy & Security › Developer Mode, tap Pair with \(jit.pairingHostName) and enter the code." + (jit.usesLocalDevVPN ? " The rest happens by itself." : " Allow the VPN when iOS asks; the rest happens by itself.")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    codeBox
                    VStack(alignment: .leading, spacing: 8) {
                        SetupRow(label: "Paired", done: jit.paired, current: flow.jitProgress == .pairing, color: color)
                        SetupRow(label: "VPN allowed", done: jit.vpnInstalled, current: flow.jitProgress == .allowingVPN, color: color)
                        SetupRow(label: "JIT ready", done: flow.jitReady, current: flow.jitProgress == .checking, color: color)
                    }
                }
                if let problem {
                    Text(problem)
                        .font(.quicksand(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } primary: {
            Button {
                if flow.jitReady { next() } else { flow.startJIT() }
            } label: {
                HStack(spacing: 10) {
                    if flow.jitRunning { ProgressView().tint(.white) }
                    Text(primaryLabel)
                }
            }
            .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
            .disabled(flow.jitRunning || !jit.debuggable)
            .opacity(flow.jitRunning ? 0.6 : 1)
        } secondary: {
            if flow.jitRunning, flow.jitProgress == .pairing {
                Button("Cancel") { flow.cancelJIT() }
            } else if !flow.jitReady, !jit.paired, !flow.jitRunning {
                Button("Use a pairing file instead") { importing = true }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .data]) { result in
            if case .success(let url) = result { flow.usePairingFile(url) }
        }
    }

    private var problem: String? {
        if !jit.debuggable {
            return "This copy of Akvavit isn't signed for development, so JIT can't work. Install it from Xcode."
        }
        return flow.jitError
    }

    private var primaryLabel: String {
        if flow.jitReady { return "Continue" }
        switch flow.jitProgress {
        case .pairing: return "Waiting for Developer Mode…"
        case .allowingVPN: return "Allowing the VPN…"
        case .checking: return "Checking JIT…"
        case .idle, .ready: return jit.paired ? "Finish JIT setup" : "Start pairing"
        }
    }

    private var code: String? {
        if case .code(let code) = jit.pairing { code } else { nil }
    }

    private var codeBox: some View {
        VStack(spacing: 2) {
            Text("Pairing code")
                .font(.quicksand(12, .bold, relativeTo: .caption))
                .foregroundStyle(AppTab.getGames.colors.icon)
            Text(code ?? "– – – – – –")
                .font(.quicksand(layout.wide ? 28 : 24, .bold, relativeTo: .title))
                .tracking(4)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
        }
        .frame(width: layout.wide ? 180 : 150)
        .padding(.vertical, 12)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 16))
        .opacity(code == nil ? 0.35 : 1)
        .accessibilityElement(children: .combine)
    }

}

/// A step's row: a circle (ticked when done, "…" while it runs) and its label.
private struct SetupRow: View {
    let label: String
    let done: Bool
    let current: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? Theme.success : current ? color : Theme.cardText.opacity(0.16))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
                } else if current {
                    Text("…").font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .animation(.easeInOut(duration: 0.3), value: done)
            Text(label)
                .font(.quicksand(16, .bold, relativeTo: .body))
                .foregroundStyle(done || current ? Theme.cardText : Theme.cardSecondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + (done ? ", done" : current ? ", in progress" : ""))
    }
}

// MARK: - LocalDevVPN

/// Only when this copy can't run Akvavit's own VPN (no Network Extensions
/// capability: a free Apple ID): LocalDevVPN from the App Store carries JIT's
/// connection instead. Get it, connect it once (iOS asks there), continue.
private struct LocalDevVPNStep: View {
    let layout: SetupLayout
    let color: Color
    let next: () -> Void
    private let jit = JIT.shared
    @State private var connecting = false

    var body: some View {
        SetupPage(layout: layout, color: color, symbol: "network", title: "Get LocalDevVPN",
                  text: "JIT needs a small VPN that only connects to this iPhone. This copy of Akvavit can’t bring its own, so it uses LocalDevVPN, a free app from the App Store.") {
            VStack(alignment: .leading, spacing: 8) {
                SetupRow(label: "Installed", done: jit.localDevVPNInstalled, current: false, color: color)
                SetupRow(label: "Connected", done: jit.localDevVPNConnected,
                         current: connecting && !jit.localDevVPNConnected, color: color)
                if connecting, !jit.localDevVPNConnected {
                    Text("Allow its VPN when iOS asks, make sure it’s connected, then come back to Akvavit.")
                        .font(.quicksand(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.cardSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        } primary: {
            Button(label) { act() }
                .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
        } secondary: {
            EmptyView()
        }
        // Installing and connecting happen in other apps: look again while shown.
        .task {
            while !Task.isCancelled {
                jit.refreshVPN()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var label: String {
        if jit.localDevVPNConnected { return "Continue" }
        return jit.localDevVPNInstalled ? "Connect LocalDevVPN" : "Get LocalDevVPN"
    }

    private func act() {
        if jit.localDevVPNConnected {
            next()
        } else if jit.localDevVPNInstalled {
            connecting = true
            jit.connectLocalDevVPN()
        } else {
            jit.getLocalDevVPN()
        }
    }
}
