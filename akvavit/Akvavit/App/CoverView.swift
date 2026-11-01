// SPDX-License-Identifier: GPL-3.0-or-later
//
// A game's cover: 2:3 art with the name and the source's badge.

import SwiftUI

struct CoverArt: View {
    let game: PlaceholderGame
    var titleSize: CGFloat = 15
    var showsBadge = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Placeholder art until step 2 brings real covers.
            LinearGradient(colors: [Color(hex: game.coverTop), Color(hex: game.coverBottom)],
                           startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
            Text(game.name)
                .font(.quicksand(titleSize, .bold, relativeTo: .headline))
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .padding(.horizontal, titleSize * 0.8)
                .padding(.bottom, showsBadge ? titleSize * 2.2 : titleSize * 1.4)
            if showsBadge {
                Text("STEAM")
                    .font(.quicksand(10, .bold, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0x0C0E1E, alpha: 0.72), in: .rect(cornerRadius: 7))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

/// A cover in a grid: tapping it opens the game's popup, which grows out of it.
struct CoverCell: View {
    let game: PlaceholderGame
    let compact: Bool
    @Environment(GamePopupModel.self) private var popup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = CGRect.zero

    var body: some View {
        Button {
            popup.show(game, from: frame, reduceMotion: reduceMotion)
        } label: {
            CoverArt(game: game, titleSize: compact ? 12 : 15)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: compact ? 10 : 12))
                .shadow(color: Theme.shadow.opacity(0.18), radius: 3, y: 2)
                .shadow(color: Theme.shadow.opacity(0.28), radius: 13, y: 12)
        }
        .buttonStyle(CoverButtonStyle())
        // The popup stands in for the cover while it is open.
        .opacity(popup.isShowing(game) ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
            frame = newFrame
            if popup.isShowing(game) { popup.sourceFrame = newFrame }
        }
        .onAppear { if popup.isShowing(game) { popup.sourceVisible = true } }
        .onDisappear { if popup.isShowing(game) { popup.sourceVisible = false } }
        .accessibilityLabel(game.name)
    }
}

private struct CoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
