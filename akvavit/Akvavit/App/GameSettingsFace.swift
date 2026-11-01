// SPDX-License-Identifier: GPL-3.0-or-later
//
// The popup's underside: the game's settings. Done tips the card back.

import SwiftUI

struct GameSettingsFace: View {
    let game: PlaceholderGame
    let layout: PopupLayout
    /// The card's final size.
    let size: CGSize
    @Bindable var model: GamePopupModel

    private static let screenSizes = ["Fit the display", "1024 × 768", "800 × 600", "640 × 480"]

    var body: some View {
        // Full spacing only on the inner display in landscape.
        let wide = layout == .wide && size.width >= 700
        VStack(alignment: .leading, spacing: wide ? 18 : 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Game settings")
                        .font(.quicksand(wide ? 26 : 22, .bold, relativeTo: .title))
                        .accessibilityAddTraits(.isHeader)
                    Text(game.name)
                        .font(.quicksand(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.cardSecondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Done") { model.hideSettings() }
                    .font(.quicksand(16, .bold, relativeTo: .body))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Theme.accent, in: .capsule)
                    .buttonStyle(.plain)
            }

            SettingRow("Reduced-precision x87",
                       detail: "Much faster Direct3D 8 games. Off computes floating point exactly, slowly.") {
                Toggle("Reduced-precision x87", isOn: $model.x87)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            SettingRow("Screen size", detail: "The size of the Windows screen the game runs on.") {
                Menu {
                    Picker("Screen size", selection: $model.screenSize) {
                        ForEach(Self.screenSizes, id: \.self) { Text($0) }
                    }
                } label: {
                    MenuLabel(model.screenSize)
                }
            }
            SettingRow("Controls", detail: "How touch reaches the game.") {
                Menu {
                    Button("Touch as mouse") {}
                } label: {
                    MenuLabel("Touch as mouse")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.cardText)
        .padding(.horizontal, wide ? 32 : 20)
        .padding(.vertical, wide ? 28 : 20)
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(_ title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.quicksand(17, .bold, relativeTo: .body))
                Text(detail)
                    .font(.quicksand(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.cardSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.tile, in: .rect(cornerRadius: 18))
    }
}

private struct MenuLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
        }
        .font(.quicksand(15, .bold, relativeTo: .body))
        .foregroundStyle(Theme.outlineText)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.outline, lineWidth: 2)
        }
    }
}
