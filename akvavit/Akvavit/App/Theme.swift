// SPDX-License-Identifier: GPL-3.0-or-later
//
// The interface's colours, background and font, in one place. Light mode is
// the designed one; dark mode's colours are placeholders until it is designed.

import SwiftUI

enum Theme {
    // Text on the background
    static let text = Color(light: 0x262A40, dark: 0xEEF0FF)
    static let secondaryText = Color(light: 0x3D4260, dark: 0xB9BFE2)

    // The popup card
    static let card = Color(light: 0xFAFAFF, dark: 0x252950, alpha: 0.97)
    static let cardText = Color(light: 0x20243A, dark: 0xEEF0FF)
    static let cardSecondaryText = Color(light: 0x4B5070, dark: 0xB9BFE2)
    static let tile = Color(light: 0x4A67D0, dark: 0x7590F2, alpha: 0.08, darkAlpha: 0.16)
    static let chip = Color(light: 0x20243A, dark: 0xFFFFFF, alpha: 0.08, darkAlpha: 0.10)
    static let chipText = Color(light: 0x3A3F5C, dark: 0xD6DAF5)
    static let outline = Color(light: 0x20243A, dark: 0xFFFFFF, alpha: 0.14, darkAlpha: 0.18)
    static let outlineText = Color(light: 0x2C3150, dark: 0xE2E5FA)
    static let destructive = Color(light: 0xA8231B, dark: 0xFF8A80)
    static let destructiveOutline = Color(light: 0xB3261E, dark: 0xFF8A80, alpha: 0.28, darkAlpha: 0.4)
    static let destructiveFill = Color(light: 0xB3261E, dark: 0xD93A30)
    static var accent: Color { homeColors.tint }
    /// Fact tiles in Get games' popup.
    /// A layout's card on the Controls tab.
    static let layoutCard = Color(light: 0xFFFFFF, dark: 0x252950, alpha: 0.7, darkAlpha: 0.7)
    static let installTile = Color(light: 0x138A78, dark: 0x3CC7B0, alpha: 0.08, darkAlpha: 0.16)

    // Get games' search field and source chips
    static let field = Color(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.6, darkAlpha: 0.1)
    static let chipBackground = Color(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.55, darkAlpha: 0.08)
    static let chipBorder = Color(light: 0x20243A, dark: 0xFFFFFF, alpha: 0.12, darkAlpha: 0.16)

    // Setup
    static let success = Color(light: 0x2F8F4E, dark: 0x4CC06E)
    static let link = Color(light: 0x3B4FB0, dark: 0x9FB2FF)
    static let fieldOnCard = Color(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 1, darkAlpha: 0.08)

    // Download marks on covers
    static let failed = Color(hex: 0xD93A30)

    // Shadows and dimming
    static let shadow = Color(light: 0x26285A, dark: 0x000000)
    static let dim = Color(light: 0x282C5A, dark: 0x000000, alpha: 0.26, darkAlpha: 0.4)
    static let cardDim = Color(light: 0x20243A, dark: 0x000000, alpha: 0.32, darkAlpha: 0.45)

    /// A tab's colours: the outline and selected fill, the pale fill and the
    /// icon when not selected.
    struct TabColors {
        let tint: Color
        let paleFill: Color
        let icon: Color
    }

    static let homeColors = TabColors(
        tint: Color(light: 0x4A67D0, dark: 0x5A76E0),
        paleFill: Color(light: 0x4A67D0, dark: 0x7590F2, alpha: 0.14, darkAlpha: 0.16),
        icon: Color(light: 0x3A55B8, dark: 0x9FB2FF))
    static let getGamesColors = TabColors(
        tint: Color(light: 0x138A78, dark: 0x2A9D8A),
        paleFill: Color(light: 0x138A78, dark: 0x3CC7B0, alpha: 0.14, darkAlpha: 0.16),
        icon: Color(light: 0x0F6F61, dark: 0x6FE0CC))
    /// Lilac (the canvas's colour scheme A).
    static let controlsColors = TabColors(
        tint: Color(light: 0x7A4FD6, dark: 0x8F63F0),
        paleFill: Color(light: 0x7A4FD6, dark: 0xA88AE8, alpha: 0.14, darkAlpha: 0.16),
        icon: Color(light: 0x5F3BB5, dark: 0xC9B3FF))
    static let settingsColors = TabColors(
        tint: Color(light: 0xC03D79, dark: 0xD24E8C),
        paleFill: Color(light: 0xC03D79, dark: 0xEC6AA6, alpha: 0.14, darkAlpha: 0.16),
        icon: Color(light: 0xA02E63, dark: 0xFF96C4))
}

/// The soft pastel background: teal and blue at the top left, through
/// periwinkle, to lilac and pink at the bottom right.
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.5, 0.5], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
    ]
    private static let light: [Color] = [
        Color(hex: 0x9FD3DD), Color(hex: 0xA7C4E7), Color(hex: 0xAAB3E9),
        Color(hex: 0xA5CBE2), Color(hex: 0xAAB3E9), Color(hex: 0xC0B8E9),
        Color(hex: 0xAAB3E9), Color(hex: 0xCBBBE9), Color(hex: 0xE6C9E6),
    ]
    private static let dark: [Color] = [
        Color(hex: 0x1C4A5A), Color(hex: 0x142A48), Color(hex: 0x1A1D44),
        Color(hex: 0x142A48), Color(hex: 0x1A1D44), Color(hex: 0x261C46),
        Color(hex: 0x1A1D44), Color(hex: 0x2A1A40), Color(hex: 0x4A2652),
    ]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points,
                     colors: colorScheme == .dark ? Self.dark : Self.light)
    }
}

// MARK: - Font

enum QuicksandWeight {
    case medium, semibold, bold

    /// The variable font's named instances (App/Fonts/Quicksand-Variable.ttf).
    var fontName: String {
        switch self {
        case .medium: "Quicksand-Medium"
        case .semibold: "Quicksand-SemiBold"
        case .bold: "Quicksand-Bold"
        }
    }
}

extension Font {
    /// Quicksand at a size that follows Dynamic Type like `style` does.
    static func quicksand(_ size: CGFloat, _ weight: QuicksandWeight = .bold,
                          relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }
}

// MARK: - Colours from hex values

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }

    /// One colour for light mode and one for dark mode.
    init(light: UInt32, dark: UInt32, alpha: Double = 1, darkAlpha: Double? = nil) {
        let lightColor = UIColor(hex: light, alpha: alpha)
        let darkColor = UIColor(hex: dark, alpha: darkAlpha ?? alpha)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
