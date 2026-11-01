// SPDX-License-Identifier: GPL-3.0-or-later
//
// Get games: the games of every linked account that aren't installed, with a
// search and a filter by source. A game's popup installs it.

import AkvavitKit
import SwiftUI

struct GetGamesView: View {
    let compact: Bool
    private let games = Games.shared
    @State private var query = ""
    @State private var source = SourceFilter.all
    @State private var signingIn = false

    enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "All", steam = "Steam", gog = "GOG"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                TabTitle("Get games", compact: true)
                SearchField(text: $query)
                    .padding(.top, 14)
            } else {
                HStack(alignment: .bottom) {
                    TabTitle("Get games", compact: false)
                    Spacer(minLength: 16)
                    SearchField(text: $query)
                        .frame(maxWidth: 260)
                }
            }
            SourceChips(selection: $source, compact: compact)
                .padding(.top, 12)
            content
        }
        .sheet(isPresented: $signingIn) {
            // Temporary: the test screen's sign-in, until setup's is built.
            NavigationStack { SteamTestView(showingGame: .constant(false)) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let shown = filtered
        if source != .gog, !signedIn {
            note("Sign in to Steam to see your games. Installed games still play from the Library.") {
                Button("Sign in to Steam") { signingIn = true }
                    .buttonStyle(FilledButtonStyle(color: Theme.getGamesColors.tint, height: 48, fontSize: 17))
                    .frame(maxWidth: 240)
            }
        } else if shown.isEmpty {
            note(emptyText)
        } else {
            GameGrid(games: shown, compact: compact)
        }
    }

    private var signedIn: Bool {
        if case .signedIn = Steam.shared.signIn { true } else { false }
    }

    private var filtered: [Game] {
        guard source != .gog else { return [] }
        let text = query.trimmingCharacters(in: .whitespaces)
        return games.available.filter { text.isEmpty || $0.name.localizedStandardContains(text) }
    }

    private var emptyText: String {
        let text = query.trimmingCharacters(in: .whitespaces)
        if source == .gog { return "No GOG games. GOG accounts can't be linked yet." }
        if games.refreshing && games.available.isEmpty { return "Loading your games…" }
        if !text.isEmpty { return "No game matches “\(text)”." }
        return "Every game you own is installed."
    }

    private func note(_ text: String) -> some View {
        note(text) { EmptyView() }
    }

    private func note(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.quicksand(17, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.cardSecondaryText)
                .accessibilityHidden(true)
            TextField("Search", text: $text)
                .font(.quicksand(16, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.cardText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.cardSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.field, in: .capsule)
        .shadow(color: Theme.shadow.opacity(0.12), radius: 7, y: 4)
    }
}

private struct SourceChips: View {
    @Binding var selection: GetGamesView.SourceFilter
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GetGamesView.SourceFilter.allCases) { filter in
                let selected = filter == selection
                Button(filter.rawValue) { selection = filter }
                    .font(.quicksand(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(selected ? Color.white : Theme.outlineText)
                    .padding(.horizontal, compact ? 14 : 16)
                    .frame(height: compact ? 34 : 36)
                    .background(selected ? Theme.getGamesColors.tint : Theme.chipBackground, in: .capsule)
                    .overlay {
                        Capsule().strokeBorder(selected ? Theme.getGamesColors.tint : Theme.chipBorder, lineWidth: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
