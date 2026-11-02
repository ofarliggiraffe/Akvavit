// SPDX-License-Identifier: GPL-3.0-or-later
//
// The studio's cards (the canvas's studio boards): the selected control's
// panel, and "Add a control". The panel's parts follow the boards for each
// kind (button, stick, trackpad); every control also has Opacity and a
// Haptics switch (the user's choices), and Duplicate and Delete. The number
// row has Width and Height, as a trackpad.

import AkvavitKit
import SwiftUI

// MARK: The selected control

struct ControlPanel: View {
    let control: Control
    let compact: Bool
    /// Changes the control (saved at once).
    let change: ((inout Control) -> Void) -> Void
    let chooseKey: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let done: () -> Void

    var body: some View {
        // Scrolls only when the display is too short for it.
        ViewThatFits(in: .vertical) {
            parts
            ScrollView { parts }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: compact ? 236 : 260)
        .background(StudioColors.floating, in: .rect(cornerRadius: compact ? 20 : 22))
        .shadow(color: .black.opacity(0.35), radius: 17, y: 16)
    }

    private var parts: some View {
        VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.quicksand(compact ? 17 : 20, .bold, relativeTo: .title3))
                        .foregroundStyle(StudioColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Button("Done", action: done)
                        .font(.quicksand(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: compact ? 32 : 36)
                        .background(Theme.controlsColors.tint, in: .capsule)
                }
                switch control.kind {
                case .button(let button): buttonParts(button)
                case .keyRow: sizeParts(widths: PanelValues.rowWidths, heights: PanelValues.rowHeights)
                case .trackpad(let pad): trackpadParts(pad)
                case .stick(let stick): stickParts(stick)
                }
                SliderRow("Opacity", "\(Int((control.opacity * 100).rounded())) %",
                          values: PanelValues.opacities, value: binding(\.opacity))
                Toggle(isOn: binding(\.haptics)) { PanelText("Haptics") }
                    .tint(Theme.controlsColors.tint)
                HStack(spacing: 10) {
                    Button("Duplicate", action: duplicate)
                        .buttonStyle(OutlineButtonStyle(fontSize: 14, height: compact ? 38 : 42))
                    Button("Delete", action: delete)
                        .buttonStyle(OutlineButtonStyle(fontSize: 14, height: compact ? 38 : 42, destructive: true))
                }
        }
        .padding(compact ? 14 : 18)
    }

    private var title: String {
        switch control.kind {
        case .button(let button):
            button.action == .keyboard ? "Keyboard button" : "\(button.title) button"
        case .keyRow: "Number row"
        case .trackpad: "Trackpad"
        case .stick: "Stick"
        }
    }

    // MARK: Kinds

    @ViewBuilder
    private func buttonParts(_ button: ControlButton) -> some View {
        PanelGroup("Presses") {
            Button(action: chooseKey) {
                HStack {
                    Text(Self.presses(button.action))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                }
                .modifier(PanelField())
            }
            .buttonStyle(.plain)
        }
        PanelGroup("Label") {
            TextField(button.action.name, text: Binding(
                get: { button.label ?? "" },
                set: { text in
                    let label = text.trimmingCharacters(in: .whitespaces)
                    changeButton { $0.label = label.isEmpty ? nil : text }
                }))
            .autocorrectionDisabled()
            .modifier(PanelField())
        }
        if Self.canLatch(button.action) {
            PanelGroup("When tapped") {
                Segments(choices: PressBehaviour.allCases, selected: button.whenTapped, title: \.title) { behaviour in
                    changeButton { $0.whenTapped = behaviour }
                }
                Text(button.whenTapped.explanation)
                    .font(.quicksand(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(StudioColors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Buttons keep their shape: Size is the longer side.
        let size = max(control.placement.width, control.placement.height)
        SliderRow("Size", "\(Int(size.rounded())) pt", values: PanelValues.buttonSizes, value: Binding(
            get: { size },
            set: { new in change { $0.placement.scale(toLongerSide: new) } }))
    }

    @ViewBuilder
    private func trackpadParts(_ pad: ControlTrackpad) -> some View {
        PanelGroup("Works as") {
            Segments(choices: [ControlTrackpad.Mode.mouse, .aim, .move], selected: pad.mode, title: \.title) { mode in
                changeTrackpad { $0.mode = mode }
            }
            Text("Mouse moves the pointer. Aim turns the view in shooters. Move holds W, A, S, D in the direction you drag.")
                .font(.quicksand(12, .semibold, relativeTo: .caption))
                .foregroundStyle(StudioColors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        SliderRow("Speed", PanelValues.speedText(pad.speed), values: PanelValues.speeds, value: Binding(
            get: { pad.speed },
            set: { speed in changeTrackpad { $0.speed = speed } }))
        sizeParts(widths: PanelValues.padSizes, heights: PanelValues.padSizes)
    }

    @ViewBuilder
    private func stickParts(_ stick: ControlStick) -> some View {
        PanelGroup("Works as") {
            VStack(spacing: 6) {
                ForEach([ControlStick.WorksAs.leftStick, .rightStick, .wasd, .arrows, .mouse], id: \.self) { worksAs in
                    let chosen = stick.worksAs == worksAs
                    Button { changeStick { $0.worksAs = worksAs } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(chosen ? Theme.controlsColors.tint : StudioColors.secondaryInk)
                            Text(worksAs.title)
                            Spacer(minLength: 0)
                        }
                        .font(.quicksand(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(StudioColors.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(chosen ? Theme.controlsColors.tint.opacity(0.1) : Theme.fieldOnCard,
                                    in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(chosen ? Theme.controlsColors.tint : Theme.outline, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
        SliderRow("Dead zone", "\(Int((stick.deadZone * 100).rounded())) %", values: PanelValues.deadZones,
                  value: Binding(get: { stick.deadZone }, set: { zone in changeStick { $0.deadZone = zone } }))
        let size = max(control.placement.width, control.placement.height)
        SliderRow("Size", "\(Int(size.rounded())) pt", values: PanelValues.stickSizes, value: Binding(
            get: { size },
            set: { new in change { $0.placement.scale(toLongerSide: new) } }))
        Toggle(isOn: Binding(get: { stick.centreWhereThumbLands },
                             set: { on in changeStick { $0.centreWhereThumbLands = on } })) {
            PanelText("Centre where your thumb lands")
        }
        .tint(Theme.controlsColors.tint)
    }

    @ViewBuilder
    private func sizeParts(widths: [Double], heights: [Double]) -> some View {
        SliderRow("Width", "\(Int(control.placement.width.rounded())) pt", values: widths, value: Binding(
            get: { control.placement.width }, set: { width in change { $0.placement.width = width } }))
        SliderRow("Height", "\(Int(control.placement.height.rounded())) pt", values: heights, value: Binding(
            get: { control.placement.height }, set: { height in change { $0.placement.height = height } }))
    }

    // MARK: Changing

    private func binding<T>(_ path: WritableKeyPath<Control, T>) -> Binding<T> {
        Binding(get: { control[keyPath: path] }, set: { value in change { $0[keyPath: path] = value } })
    }

    private func changeButton(_ edit: @escaping (inout ControlButton) -> Void) {
        change { control in
            guard case .button(var button) = control.kind else { return }
            edit(&button)
            control.kind = .button(button)
        }
    }

    private func changeTrackpad(_ edit: @escaping (inout ControlTrackpad) -> Void) {
        change { control in
            guard case .trackpad(var pad) = control.kind else { return }
            edit(&pad)
            control.kind = .trackpad(pad)
        }
    }

    private func changeStick(_ edit: @escaping (inout ControlStick) -> Void) {
        change { control in
            guard case .stick(var stick) = control.kind else { return }
            edit(&stick)
            control.kind = .stick(stick)
        }
    }

    /// What "Presses" shows.
    static func presses(_ action: ControlAction) -> String {
        switch action {
        case .key(let vk): "\(VirtualKey.name(vk)) key"
        case .pad(let button): "Controller \(button.name)"
        case .keyboard: "The iPhone keyboard"
        case .mouse, .wheel: action.name
        }
    }

    /// The wheel turns once per tap, and the keyboard button only opens the
    /// keyboard: neither can stay down.
    private static func canLatch(_ action: ControlAction) -> Bool {
        switch action {
        case .wheel, .keyboard: false
        default: true
        }
    }
}

private extension Placement {
    /// Same shape, the longer side `side` points.
    mutating func scale(toLongerSide side: Double) {
        let longer = max(width, height)
        guard longer > 0 else { return }
        width = (width * side / longer).rounded()
        height = (height * side / longer).rounded()
    }
}

private extension PressBehaviour {
    var title: String {
        switch self {
        case .press: "Press"
        case .hold: "Hold"
        case .sticky: "Sticky"
        }
    }

    var explanation: String {
        switch self {
        case .press: "Down while your finger is on it."
        case .hold: "One tap holds it down; the next tap lets go."
        case .sticky: "Stays down until the next key or click is let go. Tap it again to let go."
        }
    }
}

private extension ControlTrackpad.Mode {
    var title: String {
        switch self {
        case .mouse: "Mouse"
        case .aim: "Aim"
        case .move: "Move"
        }
    }
}

private extension ControlStick.WorksAs {
    var title: String {
        switch self {
        case .leftStick: "Controller left stick"
        case .rightStick: "Controller right stick"
        case .wasd: "W A S D keys"
        case .arrows: "Arrow keys"
        case .mouse: "Mouse (aim)"
        }
    }
}

/// The sliders' notches.
enum PanelValues {
    static let buttonSizes = Array(stride(from: 40.0, through: 120, by: 10))
    static let stickSizes = Array(stride(from: 96.0, through: 224, by: 16))
    static let padSizes = Array(stride(from: 100.0, through: 600, by: 50))
    static let rowWidths = Array(stride(from: 200.0, through: 600, by: 50))
    static let rowHeights = Array(stride(from: 24.0, through: 56, by: 8))
    static let speeds = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]
    static let deadZones = [0.1, 0.2, 0.3, 0.4, 0.5]
    static let opacities = [0.2, 0.35, 0.5, 0.65, 0.8, 1]

    static func speedText(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

// MARK: Parts

private struct PanelText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.quicksand(14, .bold, relativeTo: .subheadline))
            .foregroundStyle(StudioColors.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small heading over its part.
private struct PanelGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.quicksand(12, .bold, relativeTo: .caption))
                .foregroundStyle(StudioColors.secondaryInk)
            content
        }
    }
}

/// The white field of the boards' "Presses" and "Label".
private struct PanelField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.quicksand(15, .bold, relativeTo: .body))
            .foregroundStyle(StudioColors.ink)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Theme.fieldOnCard, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2)
            }
    }
}

/// A name and value over a notched slider.
struct SliderRow: View {
    let title: String
    let value: String
    let values: [Double]
    @Binding var current: Double

    init(_ title: String, _ value: String, values: [Double], value binding: Binding<Double>) {
        self.title = title
        self.value = value
        self.values = values
        _current = binding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(StudioColors.secondaryInk)
                Spacer()
                Text(value).foregroundStyle(StudioColors.ink).monospacedDigit()
            }
            .font(.quicksand(12, .bold, relativeTo: .caption))
            NotchedSlider(values: values, value: $current)
                .accessibilityLabel(title)
        }
    }
}

/// The boards' segmented choice: grey, the chosen one lilac.
struct Segments<Choice: Hashable>: View {
    let choices: [Choice]
    let selected: Choice
    let title: (Choice) -> String
    let choose: (Choice) -> Void

    init(choices: [Choice], selected: Choice, title: @escaping (Choice) -> String, choose: @escaping (Choice) -> Void) {
        self.choices = choices
        self.selected = selected
        self.title = title
        self.choose = choose
    }

    init(choices: [Choice], selected: Choice, title: KeyPath<Choice, String>, choose: @escaping (Choice) -> Void) {
        self.init(choices: choices, selected: selected, title: { $0[keyPath: title] }, choose: choose)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.self) { choice in
                let chosen = choice == selected
                Button(title(choice)) { choose(choice) }
                    .font(.quicksand(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(chosen ? Color.white : Theme.outlineText)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(chosen ? Theme.controlsColors.tint : .clear, in: .rect(cornerRadius: 9))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .background(StudioColors.chip, in: .rect(cornerRadius: 12))
    }
}

// MARK: Adding

/// What "Add a control" offers (the canvas's "Add a control" board).
enum AddChoice: Hashable {
    case mouse(ControlAction.MouseButton)
    case wheel(ControlAction.Wheel)
    case trackpad(ControlTrackpad.Mode)
    case stick(ControlStick.WorksAs)
    case anyKey
    case key(Int)
    case numberRow
    case keyboard
    case pad(ControlAction.PadButton)
    case dpad

    var title: String {
        switch self {
        case .mouse(let button): ControlAction.mouse(button).name
        case .wheel(let wheel): ControlAction.wheel(wheel).name
        case .trackpad(.mouse): "Mouse trackpad"
        case .trackpad(.aim): "Aim pad (turns the view)"
        case .trackpad(.move): "Move pad (WASD)"
        case .stick(.leftStick): "Controller left stick"
        case .stick(.rightStick): "Controller right stick"
        case .stick: "Stick as WASD"
        case .anyKey: "Any key…"
        case .key(let vk): VirtualKey.name(vk)
        case .numberRow: "Number row 1–0"
        case .keyboard: "Keyboard button"
        case .pad(let button): button.name
        case .dpad: "D-pad"
        }
    }

    static let groups: [(title: String, choices: [AddChoice], tinted: Bool)] = [
        ("Mouse", [.mouse(.left), .mouse(.right), .mouse(.middle), .wheel(.up), .wheel(.down)], false),
        ("Trackpads", [.trackpad(.mouse), .trackpad(.aim), .trackpad(.move)], true),
        ("Sticks", [.stick(.leftStick), .stick(.rightStick), .stick(.wasd)], false),
        ("Keys", [.anyKey, .key(VirtualKey.ctrl), .key(VirtualKey.shift), .key(VirtualKey.alt), .key(VirtualKey.escape),
                  .key(VirtualKey.space), .key(VirtualKey.enter), .numberRow, .keyboard], false),
        ("Controller buttons", [.pad(.a), .pad(.b), .pad(.x), .pad(.y), .pad(.lb), .pad(.rb), .pad(.lt), .pad(.rt),
                                .pad(.start), .pad(.back), .dpad], false),
    ]

    /// The new controls, centred at `centre` (the D-pad is four buttons).
    func controls(at centre: CGPoint, in area: CGRect) -> [Control] {
        func make(_ kind: Control.Kind, _ width: Double, _ height: Double, dx: Double = 0, dy: Double = 0) -> Control {
            let frame = CGRect(x: centre.x + dx - width / 2, y: centre.y + dy - height / 2, width: width, height: height)
            return Control(kind, Placement.anchored(frame, in: area))
        }
        switch self {
        case .mouse(let button): return [make(.button(ControlButton(.mouse(button))), 84, 84)]
        case .wheel(let wheel): return [make(.button(ControlButton(.wheel(wheel))), 64, 64)]
        case .trackpad(let mode): return [make(.trackpad(ControlTrackpad(mode)), 300, 250)]
        case .stick(let worksAs): return [make(.stick(ControlStick(worksAs)), 160, 160)]
        case .anyKey: return []
        case .key(let vk): return [Self.keyButton(vk, at: centre, in: area)]
        case .numberRow: return [make(.keyRow(.numbers), 452, 32)]
        case .keyboard: return [make(.button(ControlButton(.keyboard, shape: .rounded)), 72, 72)]
        case .pad(let button):
            switch button {
            case .a: return [make(.button(ControlButton(.pad(.a), colour: .green)), 54, 54)]
            case .b: return [make(.button(ControlButton(.pad(.b), colour: .red)), 54, 54)]
            case .x: return [make(.button(ControlButton(.pad(.x), colour: .blue)), 54, 54)]
            case .y: return [make(.button(ControlButton(.pad(.y), colour: .yellow)), 54, 54)]
            case .lb, .rb, .lt, .rt: return [make(.button(ControlButton(.pad(button), shape: .rounded)), 80, 40)]
            case .start, .back: return [make(.button(ControlButton(.pad(button), shape: .rounded)), 72, 36)]
            default: return [make(.button(ControlButton(.pad(button), shape: .rounded)), 48, 48)]
            }
        case .dpad:
            let side = 48.0, step = 52.0
            return [(ControlAction.PadButton.up, 0.0, -step), (.down, 0, step), (.left, -step, 0), (.right, step, 0)]
                .map { button, dx, dy in make(.button(ControlButton(.pad(button), shape: .rounded)), side, side, dx: dx, dy: dy) }
        }
    }

    /// A key button: modifiers lilac, as the Strategy layout's Ctrl.
    static func keyButton(_ vk: Int, at centre: CGPoint, in area: CGRect) -> Control {
        let modifier = [VirtualKey.ctrl, VirtualKey.shift, VirtualKey.alt, VirtualKey.windows].contains(vk)
        let frame = CGRect(x: centre.x - 36, y: centre.y - 36, width: 72, height: 72)
        return Control(.button(ControlButton(.key(vk), shape: .rounded, colour: modifier ? .lilac : .plain)),
                       Placement.anchored(frame, in: area))
    }
}

/// "Add a control": everything a layout can have, by kind.
struct AddControlCard: View {
    let add: (AddChoice) -> Void
    let close: () -> Void

    var body: some View {
        StudioCard(title: "Add a control", subtitle: nil, close: close) {
            ForEach(AddChoice.groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.quicksand(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(StudioColors.secondaryInk)
                    ChipFlow(spacing: 8) {
                        ForEach(group.choices, id: \.self) { choice in
                            Button(choice.title) { add(choice) }
                                .buttonStyle(CardChipStyle(tinted: group.tinted))
                        }
                    }
                }
            }
        }
    }
}

// MARK: Cards

/// A card over the dimmed studio, with a title and a close button.
struct StudioCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(hex: 0x0A0C1E, alpha: 0.35))
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.quicksand(24, .bold, relativeTo: .title2))
                            .foregroundStyle(StudioColors.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(.quicksand(14, .semibold, relativeTo: .subheadline))
                                .foregroundStyle(StudioColors.secondaryInk)
                        }
                    }
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.chipText)
                            .frame(width: 44, height: 44)
                            .background(StudioColors.chip, in: .circle)
                    }
                    .accessibilityLabel("Close")
                }
                ViewThatFits(in: .vertical) {
                    contentStack
                    ScrollView { contentStack }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 680)
            .background(Color(light: 0xFAFAFF, dark: 0x252950, alpha: 0.97), in: .rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 30)
            .padding(16)
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The cards' key-shaped choices; lilac-tinted ones stand out (trackpads, modifiers).
struct CardChipStyle: ButtonStyle {
    var tinted = false
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(14, .bold, relativeTo: .subheadline))
            .foregroundStyle(StudioColors.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .background(tinted ? Theme.controlsColors.tint.opacity(0.08) : Theme.fieldOnCard, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tinted ? Theme.controlsColors.tint.opacity(0.35) : Theme.chipBorder, lineWidth: 2)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Lays its views out in rows, wrapping at the width.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// "Delete this layout?" in the app's own style (as Uninstall in the game
/// popup), for the Controls tab's long press and the studio's "…".
struct DeleteLayoutCard: View {
    let name: String
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        ConfirmLayoutCard(title: "Delete \u{201C}\(name)\u{201D}?",
                          text: "Games that use it go back to \(BuiltInLayouts.gameDefault.name).",
                          action: "Delete", confirm: delete, cancel: cancel)
    }
}

/// Asks before a changed built-in layout goes back as the app has it.
struct RestoreLayoutCard: View {
    let name: String
    let restore: () -> Void
    let cancel: () -> Void

    var body: some View {
        ConfirmLayoutCard(title: "Restore \u{201C}\(name)\u{201D}?",
                          text: "Your changes to it are undone, and it is back as Akvavit has it.",
                          action: "Restore", confirm: restore, cancel: cancel)
    }
}

/// The card that asks before a layout is deleted or restored.
private struct ConfirmLayoutCard: View {
    let title: String
    let text: String
    let action: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Theme.cardDim
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture(perform: cancel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.quicksand(20, .bold, relativeTo: .title3))
                Text(text)
                HStack(spacing: 10) {
                    Button("Cancel", action: cancel)
                        .buttonStyle(OutlineButtonStyle(fontSize: 16, height: 46))
                    Button(action, action: confirm)
                        .buttonStyle(FilledButtonStyle(color: Theme.destructiveFill, height: 46, fontSize: 16))
                }
                .padding(.top, 8)
            }
            .font(.quicksand(15, .semibold, relativeTo: .body))
            .foregroundStyle(Theme.cardText)
            .padding(24)
            .frame(maxWidth: 380)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .shadow(color: Theme.shadow.opacity(0.35), radius: 25, y: 20)
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}
