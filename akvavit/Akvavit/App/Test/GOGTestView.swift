// SPDX-License-Identifier: GPL-3.0-or-later
//
// TEMPORARY test screen for AkvavitKit's GOG account: sign-in through GOG's
// own page in a web view, the account, and the GOG games in the list.

import AkvavitKit
import SwiftUI
import WebKit

struct GOGTestView: View {
    private let account = GOGAccount.shared
    private let games = Games.shared
    @State private var showingPage = false

    var body: some View {
        List {
            Section("Sign-in") {
                switch account.state {
                case .signedIn:
                    LabeledContent("Signed in", value: account.userName ?? "…")
                    Button("Sign out", role: .destructive) { account.signOut() }
                case .busy:
                    ProgressView()
                case .signedOut:
                    Button("Sign in to GOG") { showingPage = true }
                    if let error = account.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            if account.isSignedIn {
                Section("Games") {
                    let gog = games.available.filter { $0.source == .gog } + games.library.filter { $0.source == .gog }
                    LabeledContent("GOG games (installable)", value: "\(gog.count)")
                    Button("Refresh") { Task { await games.refresh() } }
                        .disabled(games.refreshing)
                    ForEach(gog) { game in
                        LabeledContent(game.name, value: game.releaseYear.map(String.init) ?? "")
                    }
                }
            }
        }
        .navigationTitle("GOG (test)")
        .sheet(isPresented: $showingPage) {
            NavigationStack {
                GOGSignInPage { code in
                    showingPage = false
                    Task { await account.finish(code: code) }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("GOG")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingPage = false }
                    }
                }
            }
        }
    }
}
