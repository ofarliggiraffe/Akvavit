// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Controls tab (the canvas's "Controls" board): the built-in layouts and
// your copies, each a card with a picture of its controls. A card opens the
// layout in the studio. Haptics for every layout switch on and off here.

import AkvavitKit
import SwiftUI

struct ControlsView: View {
    let compact: Bool
    /// Shows a layout in the studio (RootView shows it above everything).
    let openStudio: (String) -> Void
    @Bindable private var store = ControlLayoutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                TabTitle("Controls", detail: compact ? nil : "Copy a built-in layout to make your own.", compact: compact)
                Spacer(minLength: 16)
                Toggle(isOn: $store.haptics) {
                    Text("Haptics")
                        .font(.quicksand(15, .bold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.controlsColors.tint)
                .fixedSize()
                .padding(.top, compact ? 18 : 14)   // level with the title (TabTitle's own top space)
            }
            .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading("Built in", top: 0)
                    grid(store.builtIns)
                    heading("Your layouts", top: 24)
                    if store.yours.isEmpty {
                        LayoutGrid(compact: compact) { EmptyYours() }
                    } else {
                        grid(store.yours)
                    }
                }
                .padding(.top, compact ? 14 : 18)
                .padding(.bottom, 32)
                .padding(.horizontal, 16)   // room for the cards' shadows
            }
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: compact ? 14 : 18)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                }
            }
            .padding(.horizontal, -16)
        }
    }

    private func heading(_ text: String, top: CGFloat) -> some View {
        Text(text)
            .font(.quicksand(17, .bold, relativeTo: .headline))
            .foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, top)
            .padding(.bottom, 10)
    }

    private func grid(_ layouts: [ControlLayout]) -> some View {
        LayoutGrid(compact: compact) {
            ForEach(layouts) { layout in
                Button { openStudio(layout.id) } label: {
                    LayoutCard(layout: layout)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LayoutGrid<Content: View>: View {
    let compact: Bool
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 170), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 16) {
            content
        }
    }
}

private struct LayoutCard: View {
    let layout: ControlLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayoutThumbnail(layout: layout)
            Text(layout.name)
                .font(.quicksand(15, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.cardText)
                .lineLimit(1)
            Text(Self.summary(of: layout))
                .font(.quicksand(12, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.cardSecondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.layoutCard, in: .rect(cornerRadius: 18))
        .shadow(color: Theme.shadow.opacity(0.14), radius: 10, y: 8)
        .contentShape(.rect(cornerRadius: 18))
    }

    static func summary(of layout: ControlLayout) -> String {
        switch layout.id {
        case BuiltInLayouts.touchAsMouse.id: "Strategy and building games. No buttons on screen."
        case BuiltInLayouts.strategyTrackpad.id: "Mouse trackpad, clicks, sticky Ctrl. Number row optional."
        case BuiltInLayouts.shooterController.id: "Two sticks and Xbox buttons, for games with controller support."
        case BuiltInLayouts.shooterTrackpads.id: "One side moves, the other aims. Fire, jump and crouch."
        default: layout.copiedFrom.map { "Copy of \($0)" } ?? ""
        }
    }
}

/// A layout's controls, drawn small on the game screen's colours, in the
/// display's own shape.
struct LayoutThumbnail: View {
    let layout: ControlLayout

    var body: some View {
        let screen = Self.screenSize
        GeometryReader { geometry in
            let scale = geometry.size.width / screen.width
            ZStack {
                StudioColors.background
                if layout.controls.isEmpty {
                    touchPicture
                } else {
                    ControlsCanvas(layout: layout, area: CGRect(origin: .zero, size: screen))
                        .frame(width: screen.width, height: screen.height)
                        .scaleEffect(scale)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .aspectRatio(screen.width / screen.height, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    /// Touch as mouse has no controls: a finger and where it points.
    private var touchPicture: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: 46, height: 46)
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
            Text("Tap where you point")
                .font(.quicksand(11, .bold, relativeTo: .caption2))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
        }
    }

    /// The display the app is on, in landscape (as games are).
    private static var screenSize: CGSize {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let size = scene?.screen.bounds.size ?? CGSize(width: 951, height: 669)
        return CGSize(width: max(size.width, size.height), height: min(size.width, size.height))
    }
}

private struct EmptyYours: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Your copies show here")
                .font(.quicksand(14, .bold, relativeTo: .subheadline))
            Text("Open a built-in layout and tap Make a copy.")
                .font(.quicksand(12, .semibold, relativeTo: .footnote))
                .lineSpacing(2)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.cardSecondaryText)
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
    }
}
