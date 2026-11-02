// SPDX-License-Identifier: GPL-3.0-or-later
//
// Signing in to Steam: account and password, or Steam's QR code, then Steam
// Guard (approve in the Steam app, or a code). One page for setup's Steam
// step and for the sign-in card over Get games (SignInCard).

import AkvavitKit
import SwiftUI

struct SteamSignInStep: View {
    let layout: SetupLayout
    let color: Color
    var symbol = "person.fill"
    var logo: String? = nil
    /// Setup: Later skips the step. The card has none (its ✕ closes it).
    var later: (() -> Void)? = nil
    /// Setup: Continue, once signed in; the card calls it by itself.
    var continues = true
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
                  color: color, symbol: symbol, logo: logo, title: "Sign in to Steam",
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
                // The card closes by itself, after a moment to read it.
                if !continues {
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        next()
                    }
                }
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
            Button(continues ? "Continue" : "Done", action: next)
                .buttonStyle(FilledButtonStyle(color: color, height: 56, fontSize: 19))
        }
    }

    @ViewBuilder
    private var secondary: some View {
        switch steam.signIn {
        case .signedOut:
            // Later (setup): signing in also works from Get games.
            HStack(spacing: 0) {
                Button(layout.wide || later == nil ? "Sign in with a QR code instead" : "Use a QR code") {
                    focus = nil
                    steam.signInWithQRCode()
                }
                if let later {
                    Spacer(minLength: 8)
                    Button("Later") {
                        focus = nil
                        later()
                    }
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
