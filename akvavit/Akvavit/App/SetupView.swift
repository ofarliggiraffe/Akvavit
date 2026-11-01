// SPDX-License-Identifier: GPL-3.0-or-later
//
// Setup, on first start (and from Settings › Run setup again): a card over
// the blurred home screen whose four steps slide under dots that stay put.
// Welcome, JIT (pairing, VPN and check run as one chain), Steam, done.

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

    private var stepColors: [Color] { [Self.blue, Self.teal, Self.blue, Theme.success] }

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
                    ForEach(0..<4, id: \.self) { index in
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
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == step ? stepColors[step]
                          : Theme.cardText.opacity(index < step ? 0.35 : 0.14))
                    .frame(width: index == step ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 4")
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
        switch index {
        case 0:
            SetupPage(layout: layout, color: Self.blue, symbol: "sparkles", title: "Welcome to Akvavit",
                      text: "Akvavit runs Windows games on your iPhone with Madeira’s engine: FEX-Emu, Wine and DXMT, ported to iOS by the Madeira project. Two short steps get you ready.") {
                EmptyView()
            } primary: {
                Button("Get started") { go(to: 1) }
                    .buttonStyle(FilledButtonStyle(color: Self.blue, height: 56, fontSize: 19))
            } secondary: {
                EmptyView()
            }
        case 1:
            JITStep(layout: layout, color: Self.teal) { go(to: 2) }
        case 2:
            SteamStep(layout: layout, color: Self.blue) { go(to: 3) }
        default:
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
private struct SetupPage<Middle: View, Primary: View, Secondary: View>: View {
    let layout: SetupLayout
    let color: Color
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder let middle: Middle
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if layout.showsIcon {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
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

private struct LinkButtonStyle: ButtonStyle {
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
                  text: "Games need JIT. Turn on Wi-Fi and tap Start pairing, then open Settings › Privacy & Security › Developer Mode, tap Pair with \(jit.pairingHostName) and enter the code. Allow the VPN when iOS asks; the rest happens by itself.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    codeBox
                    VStack(alignment: .leading, spacing: 8) {
                        row("Paired", done: jit.paired, current: flow.jitProgress == .pairing)
                        row("VPN allowed", done: jit.vpnInstalled, current: flow.jitProgress == .allowingVPN)
                        row("JIT ready", done: flow.jitReady, current: flow.jitProgress == .checking)
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

    private func row(_ label: String, done: Bool, current: Bool) -> some View {
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

// MARK: - Steam

private struct SteamStep: View {
    let layout: SetupLayout
    let color: Color
    let next: () -> Void
    private let steam = Steam.shared
    @State private var account = ""
    @State private var password = ""
    @State private var guardCode = ""
    @FocusState private var focus: Field?

    private enum Field { case account, password, code }

    var body: some View {
        // With the keyboard up, the card is short; the fields matter most then.
        let typing = focus != nil
        SetupPage(layout: typing ? SetupLayout(wide: layout.wide, height: min(layout.height, 299)) : layout,
                  color: color, symbol: "person.fill", title: "Sign in to Steam",
                  text: "Your Steam games appear in Get games. The password goes only to Steam.") {
            VStack(alignment: .leading, spacing: 10) {
                middle
                if let error = steam.signInError, !isSignedIn {
                    Text(error)
                        .font(.quicksand(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } primary: {
            primary
        } secondary: {
            secondary
        }
        .onChange(of: isSignedIn, initial: true) { _, signedIn in
            if signedIn {
                focus = nil
                SetupFlow.shared.prepareSteamClient()
            }
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = steam.signIn { true } else { false }
    }

    @ViewBuilder
    private var middle: some View {
        switch steam.signIn {
        case .signedOut, .busy:
            let fields = Group {
                field("Account name") {
                    TextField("", text: $account)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .account)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                field("Password") {
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }
            }
            if layout.wide {
                HStack(spacing: 12) { fields }
            } else {
                VStack(spacing: 10) { fields }
            }
        case .qrCode(let image):
            HStack(spacing: 16) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 132, height: 132)
                    .padding(8)
                    .background(.white, in: .rect(cornerRadius: 12))
                    .accessibilityLabel("Sign-in QR code")
                Text("Scan this with the Steam app on another device: Steam Guard, then the QR code button.")
                    .font(.quicksand(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.cardSecondaryText)
            }
        case .steamGuard(let needsCode, let canApprove, let emailHint):
            VStack(alignment: .leading, spacing: 10) {
                Text(guardText(needsCode: needsCode, canApprove: canApprove, emailHint: emailHint))
                    .font(.quicksand(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.cardSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if needsCode {
                    field("Steam Guard code") {
                        TextField("", text: $guardCode)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .code)
                            .submitLabel(.go)
                            .onSubmit { steam.submitSteamGuardCode(guardCode) }
                    }
                    .frame(maxWidth: 240)
                }
            }
        case .signedIn(let account):
            Label("Signed in as \(account).", systemImage: "checkmark.circle.fill")
                .font(.quicksand(17, .bold, relativeTo: .body))
                .foregroundStyle(Theme.success)
        }
    }

    @ViewBuilder
    private var primary: some View {
        switch steam.signIn {
        case .signedOut, .busy:
            let busy = steam.signIn == .busy
            Button(action: signIn) {
                if busy { ProgressView().tint(.white) } else { Text("Sign in") }
            }
            .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
            .disabled(busy || account.isEmpty || password.isEmpty)
            .opacity(account.isEmpty || password.isEmpty ? 0.6 : 1)
        case .qrCode:
            waiting("Waiting for the Steam app…")
        case .steamGuard(let needsCode, _, _):
            if needsCode {
                Button("Submit code") { steam.submitSteamGuardCode(guardCode) }
                    .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
                    .disabled(guardCode.isEmpty)
                    .opacity(guardCode.isEmpty ? 0.6 : 1)
            } else {
                waiting("Waiting for approval…")
            }
        case .signedIn:
            Button("Continue", action: next)
                .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
        }
    }

    @ViewBuilder
    private var secondary: some View {
        switch steam.signIn {
        case .signedOut:
            // Later: signing in also works from Get games.
            HStack(spacing: 0) {
                Button(layout.wide ? "Sign in with a QR code instead" : "Use a QR code") {
                    focus = nil
                    steam.signInWithQRCode()
                }
                Spacer(minLength: 8)
                Button("Later") {
                    focus = nil
                    next()
                }
            }
        case .qrCode:
            Button("Use the password instead") { steam.cancelSignIn() }
        case .steamGuard:
            Button("Cancel") { steam.cancelSignIn() }
        case .busy, .signedIn:
            EmptyView()
        }
    }

    private func waiting(_ text: String) -> some View {
        Button {} label: {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(text)
            }
        }
        .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
        .disabled(true)
        .opacity(0.6)
    }

    private func signIn() {
        guard !account.isEmpty, !password.isEmpty else { return }
        focus = nil
        steam.signIn(account: account, password: password)
    }

    private func guardText(needsCode: Bool, canApprove: Bool, emailHint: String?) -> String {
        switch (needsCode, canApprove) {
        case (true, true): "Approve the sign-in in the Steam app, or enter the code it shows."
        case (true, false):
            emailHint.map { "Enter the code Steam sent to \($0)." } ?? "Enter the code from the Steam app."
        default: "Approve the sign-in in the Steam app."
        }
    }

    private func field(_ label: String, @ViewBuilder input: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.quicksand(13, .bold, relativeTo: .caption))
                .foregroundStyle(Theme.cardSecondaryText)
            input()
                .font(.quicksand(16, .semibold, relativeTo: .body))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.fieldOnCard, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2)
                }
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity)
    }
}
