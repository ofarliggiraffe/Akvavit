// SPDX-License-Identifier: GPL-3.0-or-later
//
// The app's one screen: the tab column on the left, the selected tab's content
// beside it, the game popup above them, the controls studio over all of that
// while it is open, a session's screen over everything while a game starts
// and runs, and setup on first start (or when run again from Settings).

import AkvavitKit
import SwiftUI

struct RootView: View {
    @SceneStorage("tab") private var tab = AppTab.home
    @State private var popup = GamePopupModel()
    /// The layout open in the controls studio, which covers everything.
    @State private var studio: String?
    /// One of your control layouts, while the card asks whether to delete it.
    @State private var deletingLayout: ControlLayout?
    /// The whole display's height: how far the studio slides.
    @State private var displayHeight: CGFloat = 1000

    private var signedIn: Bool {
        if case .signedIn = Steam.shared.signIn { true } else { false }
    }

    var body: some View {
        ZStack {
            main
            if let studio {
                // Slides in from the bottom and back out, by the whole
                // display's height: it reaches past the safe area, so a slide
                // by its own height leaves a strip of it on screen.
                ControlStudio(layoutID: studio, close: closeStudio)
                    .transition(.offset(y: displayHeight))
                    .zIndex(1)
            }
            if let layout = deletingLayout {
                DeleteLayoutCard(name: layout.name) {
                    ControlLayoutStore.shared.delete(layout.id)
                    withAnimation(.easeOut(duration: 0.2)) { deletingLayout = nil }
                } cancel: {
                    withAnimation(.easeOut(duration: 0.2)) { deletingLayout = nil }
                }
                .zIndex(2)
            }
            // A session's screen, from Play (the loading screen shows from the
            // tap) or the test screens; one session per app run. A layer, not a
            // presentation: a full-screen cover came up only once the session
            // had started.
            if Session.shared.state != .idle || StartProgress.shared.beforeSession {
                GameScreen()
                    .transition(.opacity)
                    .zIndex(3)
            }
            // Outside `main`, which ignores the keyboard: setup's card makes room for it.
            if !SetupFlow.shared.isDone {
                SetupView()
            }
        }
        .background { ThemeBackground().ignoresSafeArea() }
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom }
            action: { displayHeight = $0 }
        .onChange(of: SetupFlow.shared.isDone) { _, done in
            if !done { tab = .home }
        }
    }

    private var main: some View {
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
        .ignoresSafeArea(.keyboard)
        .environment(popup)
        // Steam's view of the games: at start, and after signing in.
        .task(id: signedIn) { await Games.shared.refresh() }
        // A session's screen, from Play or the test screens; one session per app run.
    }

    /// Landscape first, then the studio.
    private func openStudio(_ id: String) {
        guard studio == nil else { return }
        OrientationLock.lock()
        withAnimation(.easeOut(duration: 0.3)) { studio = id }
    }

    /// The landscape lock goes once the studio has gone, not during its animation.
    private func closeStudio() {
        withAnimation(.easeOut(duration: 0.3)) { studio = nil } completion: {
            OrientationLock.unlock()
        }
    }

    @ViewBuilder
    private func content(compact: Bool) -> some View {
        switch tab {
        case .home:
            LibraryView(compact: compact) { tab = .getGames }
        case .getGames:
            GetGamesView(compact: compact)
        case .controls:
            ControlsView(compact: compact, openStudio: openStudio) { layout in
                withAnimation(.easeOut(duration: 0.2)) { deletingLayout = layout }
            }
        case .settings:
            // Temporary: the test screens, until Settings is designed.
            TestHome()
        }
    }
}
