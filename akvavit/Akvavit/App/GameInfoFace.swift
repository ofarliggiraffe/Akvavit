// SPDX-License-Identifier: GPL-3.0-or-later
//
// The popup's info side: the cover, the title, the facts, Play, and below it
// Game settings and Uninstall (which asks on the card itself).

import SwiftUI

struct GameInfoFace: View {
    let game: PlaceholderGame
    let layout: PopupLayout
    /// The card's final size.
    let size: CGSize
    let model: GamePopupModel

    var body: some View {
        ZStack {
            switch layout {
            case .wide: wide
            case .tall: tall
            }
            if model.confirmingUninstall {
                UninstallConfirmation(game: game, width: min(380, size.width - 40), model: model)
            }
        }
        .foregroundStyle(Theme.cardText)
    }

    /// Landscape on the outer display: the same layout, smaller.
    private var small: Bool { size.width < 700 }

    private var wide: some View {
        let padding: CGFloat = small ? 20 : 24
        let coverWidth = min((size.height - 2 * padding) * 2 / 3, size.width * 0.36)
        return HStack(alignment: .top, spacing: small ? 20 : 28) {
            cover(width: coverWidth, height: coverWidth * 3 / 2, titleSize: small ? 16 : 22, radius: 16)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        title(size: small ? 22 : 28)
                        SourceChip()
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                    CloseButton { model.close() }
                }
                FactsRow(game: game, compact: small)
                    .padding(.top, small ? 18 : 26)
                Spacer(minLength: 16)
                actions(compact: small)
            }
        }
        .padding(padding)
    }

    private var tall: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                cover(width: 132, height: 198, titleSize: 13, radius: 14)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer(minLength: 0)
                        CloseButton { model.close() }
                    }
                    title(size: 22)
                    SourceChip()
                }
            }
            FactsRow(game: game, compact: true)
                .padding(.top, 22)
            Spacer(minLength: 16)
            actions(compact: true)
        }
        .padding(20)
    }

    private func cover(width: CGFloat, height: CGFloat, titleSize: CGFloat, radius: CGFloat) -> some View {
        CoverArt(game: game, titleSize: titleSize, showsBadge: false)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: radius))
            .shadow(color: Theme.shadow.opacity(0.35), radius: 15, y: 14)
            .accessibilityHidden(true)
    }

    private func title(size: CGFloat) -> some View {
        Text(game.name)
            .font(.quicksand(size, .bold, relativeTo: .title))
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    private func actions(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 12) {
            Button {
                // Step 3: starts the game.
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(FilledButtonStyle(color: Theme.accent, height: compact ? 56 : 58,
                                           fontSize: compact ? 19 : 20))
            HStack(spacing: compact ? 10 : 12) {
                Button {
                    model.showSettings()
                } label: {
                    Label("Game settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(OutlineButtonStyle(fontSize: compact ? 15 : 16))
                Button {
                    model.confirmingUninstall = true
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(OutlineButtonStyle(fontSize: compact ? 15 : 16, destructive: true))
            }
        }
    }
}

private struct FactsRow: View {
    let game: PlaceholderGame
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            fact("Playtime", "—")
            fact("Released", game.released)
            fact("Size on disk", game.size ?? "—")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.quicksand(compact ? 11 : 12, .bold, relativeTo: .caption))
                .tracking(0.4)
                .foregroundStyle(Theme.cardSecondaryText)
            Text(value)
                .font(.quicksand(compact ? 16 : 20, .bold, relativeTo: .title3))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 12 : 14)
        .background(Theme.tile, in: .rect(cornerRadius: compact ? 14 : 16))
        .accessibilityElement(children: .combine)
    }
}

private struct SourceChip: View {
    var body: some View {
        Text("Steam")
            .font(.quicksand(13, .bold, relativeTo: .caption))
            .foregroundStyle(Theme.chipText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.chip, in: .capsule)
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.chipText)
                .frame(width: 44, height: 44)
                .background(Theme.chip, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// Asks before uninstalling, on the card itself.
private struct UninstallConfirmation: View {
    let game: PlaceholderGame
    let width: CGFloat
    let model: GamePopupModel

    var body: some View {
        ZStack {
            Theme.cardDim
                .contentShape(.rect)
                .onTapGesture { model.confirmingUninstall = false }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text("Uninstall \(game.name)?")
                    .font(.quicksand(20, .bold, relativeTo: .title3))
                Text((game.size.map { "This deletes its \($0) of game files." } ?? "This deletes its game files.")
                     + " You can install it again from Get games.")
                HStack(spacing: 10) {
                    Button("Cancel") { model.confirmingUninstall = false }
                        .buttonStyle(OutlineButtonStyle(fontSize: 16, height: 46))
                    Button("Uninstall") {
                        // Spike: nothing is deleted yet (step 3).
                        model.close()
                    }
                    .buttonStyle(FilledButtonStyle(color: Theme.destructiveFill, height: 46, fontSize: 16))
                }
                .padding(.top, 8)
            }
            .font(.quicksand(15, .semibold, relativeTo: .body))
            .foregroundStyle(Theme.cardText)
            .padding(24)
            .frame(width: width)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .shadow(color: Theme.shadow.opacity(0.35), radius: 25, y: 20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: - Button styles

struct FilledButtonStyle: ButtonStyle {
    let color: Color
    var height: CGFloat = 58
    var fontSize: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(fontSize, .bold, relativeTo: .headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(color, in: .rect(cornerRadius: height >= 54 ? 18 : 14))
            .shadow(color: color.opacity(0.35), radius: 12, y: 10)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 16
    var height: CGFloat = 48
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(fontSize, .bold, relativeTo: .body))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(destructive ? Theme.destructive : Theme.outlineText)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(.rect)
            .overlay {
                RoundedRectangle(cornerRadius: height >= 48 ? 16 : 14)
                    .strokeBorder(destructive ? Theme.destructiveOutline : Theme.outline, lineWidth: 2)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
