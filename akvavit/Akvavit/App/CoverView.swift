// SPDX-License-Identifier: GPL-3.0-or-later
//
// A game's cover: 2:3 art with the source's badge. Until the art has loaded
// (or when there is none), a colour with the game's name stands in.

import AkvavitKit
import SwiftUI

struct CoverArt: View {
    let game: Game
    var titleSize: CGFloat = 15
    var showsBadge = true
    /// The height to decode the art for, when the view's own height changes
    /// a lot (the popup's flight); otherwise the view's height.
    var loadHeight: CGFloat?

    @Environment(\.displayScale) private var displayScale
    @State private var viewHeight: CGFloat = 0
    @State private var loaded: UIImage?

    private var pixelHeight: CGFloat { (loadHeight ?? viewHeight) * displayScale }

    var body: some View {
        let image = loaded ?? Covers.shared.cachedImage(for: game, pixelHeight: pixelHeight)
        CoverPlaceholder(game: game, titleSize: titleSize, showsTitle: image == nil)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if showsBadge {
                    Text("STEAM")
                        .font(.quicksand(10, .bold, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0x0C0E1E, alpha: 0.72), in: .rect(cornerRadius: 7))
                        .padding(8)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewHeight = $0 }
            .task(id: "\(game.id)@\(Int(pixelHeight / 100))") {
                guard pixelHeight > 0 else { return }
                if let image = await Covers.shared.image(for: game, pixelHeight: pixelHeight) {
                    loaded = image
                }
            }
    }
}

/// Colour and name, for a cover without art.
private struct CoverPlaceholder: View {
    let game: Game
    let titleSize: CGFloat
    let showsTitle: Bool

    private static let colours: [(UInt32, UInt32)] = [
        (0xC9772F, 0x4F250F), (0x2F7090, 0x13263A), (0x8E98A3, 0x333942),
        (0x4A8FD0, 0x18294A), (0xB8933A, 0x43300F), (0x8A4030, 0x26120E),
    ]

    var body: some View {
        let (top, bottom) = Self.colours[game.appID % Self.colours.count]
        LinearGradient(colors: [Color(hex: top), Color(hex: bottom)],
                       startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
            .overlay(alignment: .bottomLeading) {
                if showsTitle {
                    Text(game.name)
                        .font(.quicksand(titleSize, .bold, relativeTo: .headline))
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        .padding(.horizontal, titleSize * 0.8)
                        .padding(.bottom, titleSize * 2.2)
                }
            }
    }
}

/// A cover in a grid: tapping it opens the game's popup, which grows out of it.
struct CoverCell: View {
    let game: Game
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
