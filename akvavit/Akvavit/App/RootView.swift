// SPDX-License-Identifier: GPL-3.0-or-later
//
// The app's one screen: the tab column on the left, the selected tab's content
// beside it, and the game popup above everything.

import AkvavitKit
import SwiftUI

struct RootView: View {
    @SceneStorage("tab") private var tab = AppTab.home
    @State private var popup = GamePopupModel()

    private var signedIn: Bool {
        if case .signedIn = Steam.shared.signIn { true } else { false }
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            // The outer display is narrow; the inner one, unfolded, is not.
            let compact = proxy.size.width + insets.leading + insets.trailing < 600
            HStack(spacing: 0) {
                TabColumn(selection: $tab, compact: compact, leadingInset: insets.leading)
                    .padding(.leading, -insets.leading)
                content(compact: compact)
                    .padding(.leading, compact ? 16 : 28)
                    .padding(.trailing, compact ? 18 : 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay {
                GamePopupLayer(model: popup, safeArea: insets)
                    .ignoresSafeArea()
            }
            .onChange(of: proxy.size) { popup.layoutChanged() }
        }
        .background { ThemeBackground().ignoresSafeArea() }
        .environment(popup)
        // Steam's view of the games: at start, and after signing in.
        .task(id: signedIn) { await Games.shared.refresh() }
    }

    @ViewBuilder
    private func content(compact: Bool) -> some View {
        switch tab {
        case .home:
            LibraryView(compact: compact) { tab = .getGames }
        case .getGames:
            ComingLater(title: "Get games", note: "Comes in a later step.", compact: compact)
        case .controls:
            ComingLater(title: "Controls", note: "Coming later.", compact: compact)
        case .settings:
            // Temporary: the test screens, until Settings is designed.
            TestHome()
        }
    }
}

private struct ComingLater: View {
    let title: String
    let note: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabTitle(title, compact: compact)
            Text(note)
                .font(.quicksand(17, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
