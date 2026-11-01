// SPDX-License-Identifier: GPL-3.0-or-later
//
// Home: the installed games, from every source.

import AkvavitKit
import SwiftUI

struct LibraryView: View {
    let compact: Bool
    let showGetGames: () -> Void
    private let games = Games.shared

    var body: some View {
        let library = games.library
        VStack(alignment: .leading, spacing: 0) {
            TabTitle("Library", detail: library.count == 1 ? "1 game" : "\(library.count) games",
                     compact: compact)
            if library.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Games you install show up here.")
                        .font(.quicksand(17, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.secondaryText)
                    Button("Get games", action: showGetGames)
                        .buttonStyle(FilledButtonStyle(color: Theme.getGamesColors.tint, height: 48, fontSize: 17))
                        .frame(maxWidth: 220)
                }
                .padding(.top, 20)
            } else {
                GameGrid(games: library, compact: compact)
            }
        }
    }
}

/// A tab's title, with an optional note after it.
struct TabTitle: View {
    let title: String
    let detail: String?
    let compact: Bool

    init(_ title: String, detail: String? = nil, compact: Bool) {
        self.title = title
        self.detail = detail
        self.compact = compact
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 12 : 14) {
            Text(title)
                .font(.quicksand(compact ? 28 : 32, .bold, relativeTo: .largeTitle))
                .tracking(0.2)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.quicksand(compact ? 14 : 15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.top, compact ? 18 : 14)
    }
}
