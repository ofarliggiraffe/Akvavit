// SPDX-License-Identifier: GPL-3.0-or-later
//
// Covers in a grid whose columns follow the width. The grid fades out at its
// top and bottom edges.

import SwiftUI

struct GameGrid: View {
    let games: [PlaceholderGame]
    let compact: Bool

    var body: some View {
        let topFade: CGFloat = compact ? 20 : 22
        let bottomFade: CGFloat = compact ? 36 : 40
        // Room at the sides for the covers' shadows, which the mask would cut.
        let shadowRoom: CGFloat = 16
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 100 : 135),
                                         spacing: compact ? 14 : 18)],
                      spacing: compact ? 16 : 20) {
                ForEach(games) { game in
                    CoverCell(game: game, compact: compact)
                }
            }
            .padding(.top, topFade)
            .padding(.bottom, bottomFade)
            .padding(.horizontal, shadowRoom)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: topFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottomFade)
            }
        }
        .padding(.horizontal, -shadowRoom)
    }
}
