// SPDX-License-Identifier: GPL-3.0-or-later
//
// The sign-in cards over everything (the user's option A on the canvas): from
// Get games, Steam's in setup's card (SteamSignInStep), GOG's with GOG's own
// page in it (GOG requires it: no fields of ours). A sign-in closes the card,
// and Get games fills with that store's games. The ✕ cancels.

import AkvavitKit
import SwiftUI
import WebKit

/// Which sign-in card shows, if any.
@MainActor @Observable
final class SignInCards {
    static let shared = SignInCards()
    enum Store { case steam, gog }
    private(set) var store: Store?

    func open(_ store: Store) {
        withAnimation(.easeOut(duration: 0.3)) { self.store = store }
    }

    func close() {
        withAnimation(.easeIn(duration: 0.25)) { store = nil }
    }
}

/// The card over the blurred app.
struct SignInCardLayer: View {
    let store: SignInCards.Store
    private let cards = SignInCards.shared

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 640
            let size = Self.size(store, wide: wide, in: proxy.size)
            ZStack {
                // Only the ✕ closes the card; a stray tap beside it does nothing.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Theme.dim)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture {}
                    .accessibilityHidden(true)
                Group {
                    switch store {
                    case .steam:
                        SteamSignInStep(layout: SetupLayout(wide: wide, height: size.height), color: Theme.getGamesColors.tint,
                                        logo: "StoreSteam", continues: false) { cards.close() }
                    case .gog:
                        GOGSignInCard(wide: wide)
                    }
                }
                .frame(width: size.width, height: size.height)
                .background(Theme.card, in: .rect(cornerRadius: 28))
                .clipShape(.rect(cornerRadius: 28))
                .overlay(alignment: .topTrailing) {
                    if store == .steam {
                        CloseButton(action: cancel)
                            .padding(wide ? 20 : 16)
                    }
                }
                .shadow(color: Theme.shadow.opacity(0.35), radius: 40, y: 30)
                .foregroundStyle(Theme.cardText)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Setup's card for Steam; GOG's page needs more room.
    private static func size(_ store: SignInCards.Store, wide: Bool, in space: CGSize) -> CGSize {
        switch store {
        case .steam:
            CGSize(width: wide ? 600 : min(space.width - 28, 520),
                   height: wide ? min(452, space.height - 32) : min(space.height - 48, 600))
        case .gog:
            CGSize(width: wide ? 680 : space.width - 28,
                   height: wide ? min(589, space.height - 40) : space.height - 48)
        }
    }

    /// A sign-in under way stops with the card.
    private func cancel() {
        switch Steam.shared.signIn {
        case .signedIn, .signedOut: break
        default: Steam.shared.cancelSignIn()
        }
        cards.close()
    }
}

/// GOG's own sign-in page in the card, under a header of ours.
private struct GOGSignInCard: View {
    let wide: Bool
    private let account = GOGAccount.shared
    private let cards = SignInCards.shared
    /// A new page after a failed sign-in.
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 14 : 12) {
            HStack(spacing: 12) {
                Image("StoreGOG")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: wide ? 28 : 24, height: wide ? 28 : 24)
                    .foregroundStyle(Theme.getGamesColors.tint)
                    .frame(width: wide ? 44 : 40, height: wide ? 44 : 40)
                    .background(Theme.getGamesColors.tint.opacity(0.14), in: .rect(cornerRadius: wide ? 14 : 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to GOG")
                        .font(.quicksand(wide ? 22 : 20, .bold, relativeTo: .title2))
                        .accessibilityAddTraits(.isHeader)
                    Text(wide ? "This is GOG’s own page. The password goes only to GOG."
                              : "GOG’s own page. The password goes only to GOG.")
                        .font(.quicksand(wide ? 13 : 12, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.cardSecondaryText)
                }
                Spacer(minLength: 8)
                CloseButton { cards.close() }
            }
            ZStack {
                GOGSignInPage { code in
                    Task {
                        await account.finish(code: code)
                        if account.isSignedIn { cards.close() } else { attempt += 1 }
                    }
                }
                .id(attempt)
                if account.state == .busy {
                    Color.white.opacity(0.85)
                    ProgressView("Signing in…")
                        .font(.quicksand(15, .bold, relativeTo: .body))
                        .foregroundStyle(Theme.cardText)
                }
            }
            .clipShape(.rect(cornerRadius: wide ? 18 : 16))
            .overlay {
                RoundedRectangle(cornerRadius: wide ? 18 : 16).strokeBorder(Theme.outline, lineWidth: 2)
            }
            if let error = account.error, account.state == .signedOut {
                Text(error)
                    .font(.quicksand(14, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, wide ? 24 : 18)
        .padding(.top, wide ? 20 : 18)
        .padding(.bottom, wide ? 22 : 18)
    }
}

/// GOG's sign-in page. It stops at the page GOG ends on and hands over the
/// code. Nothing of the page (cookies, storage) is kept afterwards.
struct GOGSignInPage: UIViewRepresentable {
    let done: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: GOGAccount.shared.signInURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let done: (String) -> Void
        private var finished = false

        init(done: @escaping (String) -> Void) { self.done = done }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let code = GOGAccount.shared.signInCode(in: url) else { return .allow }
            if !finished {
                finished = true
                done(code)
            }
            return .cancel
        }
    }
}
