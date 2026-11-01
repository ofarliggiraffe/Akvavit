// SPDX-License-Identifier: GPL-3.0-or-later
//
// The controls studio (the canvas's "Controls studio" boards): a layout on the
// whole display, at the size its controls have over a game, in landscape.
// Floating on it: back and the layout's name at the top left, and for your
// own layouts a "…" with the layout's settings (touch on the game, haptics,
// delete). A built-in layout can't change; the bar at the bottom makes a copy,
// which opens here at once with its name ready to type over.

import AkvavitKit
import SwiftUI

/// The game screen's colours, behind controls in the studio and on cards.
enum StudioColors {
    static let background = LinearGradient(colors: [Color(hex: 0x3B4B5A), Color(hex: 0x1C232B)],
                                           startPoint: UnitPoint(x: 0.35, y: 0), endPoint: UnitPoint(x: 0.65, y: 1))
    /// The floating parts follow light and dark mode, as the cards do.
    static let floating = Color(light: 0xFAFAFF, dark: 0x252950, alpha: 0.94)
    static let ink = Theme.cardText
    static let secondaryInk = Theme.cardSecondaryText
    static let chip = Theme.chip
}

struct ControlStudio: View {
    @State private var layoutID: String
    @State private var name = ""
    @State private var nameSelection: TextSelection?
    @FocusState private var naming: Bool
    @State private var showingMenu = false
    @State private var confirmingDelete = false
    private let close: () -> Void
    private let store = ControlLayoutStore.shared

    init(layoutID: String, close: @escaping () -> Void) {
        _layoutID = State(initialValue: layoutID)
        self.close = close
    }

    private var layout: ControlLayout? { store.layout(id: layoutID) }

    var body: some View {
        // The whole display, as over a game.
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                StudioBackground()
                if let layout {
                    ControlsCanvas(layout: layout, area: CGRect(origin: .zero, size: proxy.size))
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { topBar }
        .overlay(alignment: .bottomLeading) {
            if layout?.isBuiltIn == true { builtInBar }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // Landscape is locked by whoever shows the studio, before it shows.
        .onAppear { name = layout?.name ?? "" }
        .onChange(of: naming) { _, focused in
            if !focused { saveName() }
        }
        .alert("Delete \u{201C}\(layout?.name ?? "")\u{201D}?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                store.delete(layoutID)
                close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Games that use it go back to Touch as mouse.")
        }
    }

    // MARK: Floating parts

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                saveName()
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.outlineText)
                    .frame(width: 44, height: 44)
                    .background(StudioColors.floating, in: .circle)
            }
            .accessibilityLabel("Back to Controls")
            if layout?.isBuiltIn == false {
                TextField("Layout name", text: $name, selection: $nameSelection)
                    .focused($naming)
                    .submitLabel(.done)
                    .onSubmit { saveName() }
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .modifier(NamePill())
                Button { showingMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.outlineText)
                        .frame(width: 44, height: 44)
                        .background(StudioColors.floating, in: .circle)
                }
                .accessibilityLabel("Layout settings")
                .popover(isPresented: $showingMenu) {
                    if let layout {
                        LayoutMenu(layout: layout) {
                            showingMenu = false
                            confirmingDelete = true
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
            } else {
                Text(layout?.name ?? "")
                    .lineLimit(1)
                    .modifier(NamePill())
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
        .padding(.leading, 24)
        .padding(.top, 18)
    }

    private var builtInBar: some View {
        HStack(spacing: 12) {
            Text("Built in, can't be changed")
                .font(.quicksand(13, .bold, relativeTo: .footnote))
                .foregroundStyle(Theme.outlineText)
                .padding(.leading, 12)
            Button("Make a copy", action: makeCopy)
                .font(.quicksand(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Theme.controlsColors.tint, in: .capsule)
        }
        .padding(7)
        .background(StudioColors.floating, in: .capsule)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
        .padding(.leading, 24)
        .padding(.bottom, 18)
    }

    // MARK: Actions

    private func makeCopy() {
        guard let layout else { return }
        let copy = store.copy(layout)
        layoutID = copy.id
        name = copy.name
        naming = true
        // Selected, so typing replaces it.
        DispatchQueue.main.async {
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    private func saveName() {
        guard let layout, !layout.isBuiltIn else { return }
        store.rename(layoutID, to: name)
        name = store.layout(id: layoutID)?.name ?? name
    }
}

/// The name, in the white pill of the studio board.
private struct NamePill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.quicksand(17, .bold, relativeTo: .headline))
            .foregroundStyle(StudioColors.ink)
            .padding(.horizontal, 14)
            .frame(width: 210, height: 44, alignment: .leading)
            .background(StudioColors.floating, in: .rect(cornerRadius: 12))
    }
}

/// The whole layout's settings, from "…".
private struct LayoutMenu: View {
    let layout: ControlLayout
    let delete: () -> Void
    private let store = ControlLayoutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Touch on the game")
                    .font(.quicksand(12, .bold, relativeTo: .caption))
                    .foregroundStyle(StudioColors.secondaryInk)
                HStack(spacing: 0) {
                    segment("As mouse", .mouse)
                    segment("Off", .off)
                }
                .padding(3)
                .background(StudioColors.chip, in: .rect(cornerRadius: 12))
            }
            Toggle(isOn: Binding(get: { layout.haptics }, set: { on in change { $0.haptics = on } })) {
                Text("Haptics for this layout")
                    .font(.quicksand(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(StudioColors.ink)
            }
            .tint(Theme.controlsColors.tint)
            Button("Delete layout", action: delete)
                .buttonStyle(OutlineButtonStyle(fontSize: 14, height: 42, destructive: true))
        }
        .padding(18)
        .frame(width: 260)
        .presentationBackground(StudioColors.floating)
    }

    private func segment(_ title: String, _ touch: ControlLayout.GameTouch) -> some View {
        let selected = layout.gameTouch == touch
        return Button(title) { change { $0.gameTouch = touch } }
            .font(.quicksand(13, .bold, relativeTo: .footnote))
            .foregroundStyle(selected ? Color.white : Theme.outlineText)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(selected ? Theme.controlsColors.tint : .clear, in: .rect(cornerRadius: 9))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func change(_ edit: (inout ControlLayout) -> Void) {
        var changed = layout
        edit(&changed)
        store.update(changed)
    }
}

/// The game screen's background with the grid's dots.
private struct StudioBackground: View {
    var body: some View {
        ZStack {
            StudioColors.background
            Canvas { context, size in
                let spacing: CGFloat = 24
                var dots = Path()
                for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                    for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                        dots.addEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                    }
                }
                context.fill(dots, with: .color(.white.opacity(0.22)))
            }
        }
        .accessibilityHidden(true)
    }
}
