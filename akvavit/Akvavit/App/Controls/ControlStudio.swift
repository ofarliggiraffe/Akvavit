// SPDX-License-Identifier: GPL-3.0-or-later
//
// The controls studio (the canvas's "Controls studio" boards): a layout on the
// whole display, at the size its controls have over a game, in landscape.
// Floating on it: back and the layout's name at the top left, and a "…" with
// the layout's settings (touch on the game, haptics; Make a copy, which opens
// here at once with its name ready to type over; for your layouts Delete, for
// a changed built-in one Restore defaults). Built-in layouts are edited like
// yours (the user, 2026-11-02), but keep their names. The tool bar at the top
// right: snap to grid and its spacing, and Mirror (on narrow displays a
// shorter bar, as the phone board shows). The bars sit along the top, out of
// the way of the controls, which mostly go at the bottom (the user's choice).
// While a finger is on a control, the bars all but disappear.

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
    @State private var confirmingRestore = false
    @State private var model = StudioModel()
    /// "Add a control" is open.
    @State private var adding = false
    /// The key picker is open: for a new button (nil) or for this control.
    @State private var choosingKey: KeyFor?
    /// The display, for placing new controls.
    @State private var area = CGRect.zero
    /// A narrow display: the shorter tool bar.
    @State private var compact = false
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
            let area = CGRect(origin: .zero, size: proxy.size)
            ZStack(alignment: .topLeading) {
                StudioBackground(spacing: model.snaps ? model.spacing : nil)
                if let layout {
                    StudioEditor(layout: layout, area: area, model: model, save: store.update)
                    panel(layout, area: area)
                }
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGRect.self) { CGRect(origin: .zero, size: $0.size) } action: { area in
            self.area = area
            compact = area.width < 900
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                floating(topBar)
                Spacer(minLength: 0)
                if layout != nil { floating(toolBar) }
            }
            .padding(.horizontal, compact ? 16 : 24)
            .padding(.top, compact ? 14 : 18)
        }
        .overlay {
            if confirmingDelete {
                DeleteLayoutCard(name: layout?.name ?? "") {
                    store.delete(layoutID)
                    close()
                } cancel: {
                    withAnimation(.easeOut(duration: 0.2)) { confirmingDelete = false }
                }
            } else if confirmingRestore {
                RestoreLayoutCard(name: layout?.name ?? "") {
                    model.selected = nil
                    store.restore(layoutID)
                    withAnimation(.easeOut(duration: 0.2)) { confirmingRestore = false }
                } cancel: {
                    withAnimation(.easeOut(duration: 0.2)) { confirmingRestore = false }
                }
            } else if adding {
                AddControlCard(add: add) { adding = false }
            } else if let target = choosingKey {
                KeyPicker(subtitle: keySubtitle(target), allActions: target.control != nil,
                          pick: { action in pickKey(action, for: target) }, close: { choosingKey = nil })
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // Landscape is locked by whoever shows the studio, before it shows.
        .onAppear { name = layout?.name ?? "" }
        .onChange(of: naming) { _, focused in
            if !focused { saveName() }
        }
    }

    // MARK: Floating parts

    /// Floating parts all but disappear while a finger is on a control.
    private func floating(_ part: some View) -> some View {
        part
            .opacity(model.isInteracting ? 0.15 : 1)
            .allowsHitTesting(!model.isInteracting)
            .animation(.easeOut(duration: 0.15), value: model.isInteracting)
    }

    /// The selected control's panel, on the side away from it, under the top bars.
    @ViewBuilder
    private func panel(_ layout: ControlLayout, area: CGRect) -> some View {
        if let id = model.selected, let control = layout.controls.first(where: { $0.id == id }) {
            let onRight = model.frame(of: control, in: area).midX < area.midX
            floating(ControlPanel(control: control, compact: compact,
                                  change: { edit in change(id, edit) },
                                  chooseKey: { choosingKey = KeyFor(control: id) },
                                  duplicate: { duplicate(control) },
                                  delete: { delete(id) },
                                  done: { model.selected = nil }))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: onRight ? .topTrailing : .topLeading)
                .padding(.top, compact ? 68 : 82)
                .padding(.bottom, compact ? 14 : 18)
                .padding(.horizontal, compact ? 16 : 24)
        }
    }

    private var toolBar: some View {
        @Bindable var model = model
        return HStack(spacing: compact ? 10 : 12) {
            Button("+ Add") {
                model.selected = nil
                adding = true
            }
            .font(.quicksand(14, .bold, relativeTo: .subheadline))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(height: compact ? 36 : 38)
            .background(Theme.controlsColors.tint, in: .capsule)
            Text(compact ? "Grid" : "Snap to grid")
                .font(.quicksand(13, .bold, relativeTo: .footnote))
                .foregroundStyle(Theme.outlineText)
                .padding(.leading, 6)
            Toggle("Snap to grid", isOn: $model.snaps)
                .labelsHidden()
                .tint(Theme.controlsColors.tint)
            if !compact {
                NotchedSlider(values: StudioModel.spacings, value: $model.spacing)
                    .frame(width: 110)
                    .opacity(model.snaps ? 1 : 0.4)
                    .disabled(!model.snaps)
                    .accessibilityLabel("Grid spacing")
                Text("\(Int(model.spacing)) pt")
                    .font(.quicksand(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(StudioColors.secondaryInk)
                    .monospacedDigit()
            }
            Button(compact ? "Mirror" : "Mirror sides", action: mirror)
                .buttonStyle(ChipButtonStyle(compact: compact))
        }
        .padding(.horizontal, 8)
        .frame(height: compact ? 44 : 52)
        .background(StudioColors.floating, in: .capsule)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
    }

    /// The round buttons' size (the phone board's are smaller).
    private var round: CGFloat { compact ? 40 : 44 }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                saveName()
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.outlineText)
                    .frame(width: round, height: round)
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
                    .modifier(NamePill(compact: compact))
            } else {
                Text(layout?.name ?? "")
                    .lineLimit(1)
                    .modifier(NamePill(compact: compact))
            }
            Button { showingMenu = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.outlineText)
                    .frame(width: round, height: round)
                    .background(StudioColors.floating, in: .circle)
            }
            .accessibilityLabel("Layout settings")
            .popover(isPresented: $showingMenu) {
                if let layout {
                    LayoutMenu(layout: layout, makeCopy: {
                        showingMenu = false
                        makeCopy()
                    }, restore: {
                        showingMenu = false
                        withAnimation(.easeOut(duration: 0.2)) { confirmingRestore = true }
                    }, delete: {
                        showingMenu = false
                        withAnimation(.easeOut(duration: 0.2)) { confirmingDelete = true }
                    })
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
    }

    // MARK: Actions

    // Changing controls (each change is saved at once).

    private func change(_ id: UUID, _ edit: (inout Control) -> Void) {
        guard var layout, let index = layout.controls.firstIndex(where: { $0.id == id }) else { return }
        edit(&layout.controls[index])
        store.update(layout)
    }

    /// New controls in the middle of the display, the (last) one selected.
    private func insert(_ controls: [Control]) {
        guard var layout, !controls.isEmpty else { return }
        layout.controls += controls
        store.update(layout)
        model.selected = controls.last?.id
    }

    private func add(_ choice: AddChoice) {
        adding = false
        if choice == .anyKey {
            choosingKey = KeyFor(control: nil)
        } else {
            insert(choice.controls(at: CGPoint(x: area.midX, y: area.midY), in: area))
        }
    }

    private func pickKey(_ action: ControlAction, for target: KeyFor) {
        choosingKey = nil
        if let id = target.control {
            change(id) { control in
                guard case .button(var button) = control.kind else { return }
                button.action = action
                // The wheel and the keyboard button can't stay down.
                switch action {
                case .keyboard, .wheel: button.whenTapped = .press
                default: break
                }
                control.kind = .button(button)
            }
        } else if case .key(let vk) = action {
            insert([AddChoice.keyButton(vk, at: CGPoint(x: area.midX, y: area.midY), in: area)])
        }
    }

    private func keySubtitle(_ target: KeyFor) -> String {
        guard let id = target.control, let control = layout?.controls.first(where: { $0.id == id }),
              case .button(let button) = control.kind else { return "For the new button" }
        return "For the \(button.title) button"
    }

    /// A copy a grid step down and to the right, selected.
    private func duplicate(_ control: Control) {
        var copy = control
        copy.id = UUID()
        let step = CGFloat(model.snaps ? model.spacing : 24)
        let frame = control.placement.frame(in: area).offsetBy(dx: step, dy: step)
        copy.placement = Placement.anchored(frame, in: area)
        insert([copy])
    }

    private func delete(_ id: UUID) {
        guard var layout else { return }
        layout.controls.removeAll { $0.id == id }
        store.update(layout)
        model.selected = nil
    }

    private func mirror() {
        guard let layout else { return }
        store.update(StudioModel.mirrored(layout))
    }

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

/// What the key picker chooses for: a control, or a new button (nil).
private struct KeyFor {
    let control: UUID?
}

/// The name, in the white pill of the studio boards.
private struct NamePill: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        content
            .font(.quicksand(compact ? 15 : 17, .bold, relativeTo: .headline))
            .foregroundStyle(StudioColors.ink)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(width: compact ? 170 : 210, height: compact ? 40 : 44, alignment: .leading)
            .background(StudioColors.floating, in: .rect(cornerRadius: 12))
    }
}

/// The whole layout's settings, from "…".
private struct LayoutMenu: View {
    let layout: ControlLayout
    let makeCopy: () -> Void
    let restore: () -> Void
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
            Button("Make a copy", action: makeCopy)
                .buttonStyle(OutlineButtonStyle(fontSize: 14, height: 42))
            if !layout.isBuiltIn {
                Button("Delete layout", action: delete)
                    .buttonStyle(OutlineButtonStyle(fontSize: 14, height: 42, destructive: true))
            } else if store.isChanged(layout.id) {
                Button("Restore defaults", action: restore)
                    .buttonStyle(OutlineButtonStyle(fontSize: 14, height: 42, destructive: true))
            }
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

/// The game screen's background, with the grid's dots while snapping is on.
/// The grid is centred on the display, as StudioModel snaps to it.
private struct StudioBackground: View {
    let spacing: Double?

    var body: some View {
        ZStack {
            StudioColors.background
            if let spacing {
                Canvas { context, size in
                    let step = CGFloat(spacing)
                    var dots = Path()
                    for x in stride(from: (size.width / 2).truncatingRemainder(dividingBy: step), through: size.width, by: step) {
                        for y in stride(from: (size.height / 2).truncatingRemainder(dividingBy: step), through: size.height, by: step) {
                            dots.addEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                        }
                    }
                    context.fill(dots, with: .color(.white.opacity(0.22)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The tool bar's buttons: grey chips.
private struct ChipButtonStyle: ButtonStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(compact ? 12 : 13, .bold, relativeTo: .footnote))
            .foregroundStyle(Theme.outlineText)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 36 : 38)
            .background(StudioColors.chip, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
