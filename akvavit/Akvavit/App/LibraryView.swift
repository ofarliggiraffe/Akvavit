// SPDX-License-Identifier: GPL-3.0-or-later
//
// Home: the installed games, from every source.

import SwiftUI

struct LibraryView: View {
    let compact: Bool
    // Step 2 replaces these with the installed games.
    private let games = PlaceholderGame.library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabTitle("Library", detail: games.count == 1 ? "1 game" : "\(games.count) games",
                     compact: compact)
            GameGrid(games: games, compact: compact)
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
