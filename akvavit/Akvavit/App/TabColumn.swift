// SPDX-License-Identifier: GPL-3.0-or-later
//
// The tabs down the left edge, in their own column: icon-only tabs that come
// out of the edge, the selected one filled and further out.

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, getGames, controls, settings

    var id: Self { self }

    var label: String {
        switch self {
        case .home: "Home"
        case .getGames: "Get games"
        case .controls: "Controls"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .getGames: "tray.and.arrow.down"
        case .controls: "gamecontroller"
        case .settings: "gearshape"
        }
    }

    var colors: Theme.TabColors {
        switch self {
        case .home: Theme.homeColors
        case .getGames: Theme.getGamesColors
        case .controls: Theme.controlsColors
        case .settings: Theme.settingsColors
        }
    }
}

struct TabColumn: View {
    @Binding var selection: AppTab
    let compact: Bool
    /// The safe area to the left: the tabs reach the display's edge under it.
    let leadingInset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AppTab.allCases) { tab in
                TabButton(tab: tab, selected: tab == selection, compact: compact,
                          leadingInset: leadingInset) {
                    selection = tab
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct TabButton: View {
    let tab: AppTab
    let selected: Bool
    let compact: Bool
    let leadingInset: CGFloat
    let action: () -> Void

    /// How far the tab comes out of the edge.
    private var width: CGFloat {
        switch (compact, selected) {
        case (false, true): 84
        case (false, false): 68
        case (true, true): 76
        case (true, false): 60
        }
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomTrailingRadius: 18, topTrailingRadius: 18)
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: compact ? 21 : 23, weight: .semibold))
                .foregroundStyle(selected ? Color.white : tab.colors.icon)
                .padding(.trailing, selected ? (compact ? 18 : 20) : (compact ? 14 : 16))
                .frame(width: leadingInset + width + 16, height: 58, alignment: .trailing)
                .background {
                    // The left edge (and its outline) sits beyond the display's edge.
                    shape.fill(selected ? tab.colors.tint : tab.colors.paleFill)
                        .strokeBorder(tab.colors.tint, lineWidth: 2)
                        .shadow(color: tab.colors.tint.opacity(selected ? 0.35 : 0), radius: 10, y: 8)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.leading, -16)
        .animation(.snappy(duration: 0.25), value: selected)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
