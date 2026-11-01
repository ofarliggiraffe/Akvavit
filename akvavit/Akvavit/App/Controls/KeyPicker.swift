// SPDX-License-Identifier: GPL-3.0-or-later
//
// "Choose a key" (the canvas's key picker board): type the key on the
// iPhone's keyboard (letters, numbers, punctuation, as on a US keyboard), or
// pick a special one (function keys, arrows, modifiers, the rest). For a
// button that exists, what it presses can also become a click, the wheel, a
// controller button or the Keyboard button (the "Add a control" groups).

import AkvavitKit
import SwiftUI
import UIKit

struct KeyPicker: View {
    /// Under the title: what the key is for.
    let subtitle: String
    /// Offer clicks, the wheel, controller buttons and the keyboard too.
    let allActions: Bool
    let pick: (ControlAction) -> Void
    let close: () -> Void

    @State private var typing = false

    var body: some View {
        StudioCard(title: "Choose a key", subtitle: subtitle, close: close) {
            Segments(choices: [true, false], selected: typing,
                     title: { $0 ? "Type it on the keyboard" : "Special keys" }) { typing = $0 }
            if typing {
                VStack(spacing: 8) {
                    Text("Press a key on the keyboard")
                        .font(.quicksand(18, .bold, relativeTo: .headline))
                        .foregroundStyle(StudioColors.ink)
                    Text("Letters, numbers and punctuation, as on a US keyboard.")
                        .font(.quicksand(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(StudioColors.secondaryInk)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(KeyCatcher(pick: pick))
            } else {
                specialKeys
            }
        }
    }

    @ViewBuilder
    private var specialKeys: some View {
        group("Function keys") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 12), spacing: 6) {
                ForEach(0..<12, id: \.self) { n in key(VirtualKey.f1 + n, fill: true) }
            }
        }
        HStack(alignment: .top, spacing: 24) {
            group("Arrows") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 44, height: 38)
                        key(VirtualKey.up, label: "↑", width: 44)
                        Color.clear.frame(width: 44, height: 38)
                    }
                    GridRow {
                        key(VirtualKey.left, label: "←", width: 44)
                        key(VirtualKey.down, label: "↓", width: 44)
                        key(VirtualKey.right, label: "→", width: 44)
                    }
                }
            }
            group("Modifiers") {
                ChipFlow(spacing: 6) {
                    ForEach([VirtualKey.ctrl, VirtualKey.shift, VirtualKey.alt, VirtualKey.windows], id: \.self) { vk in
                        key(vk, tinted: true)
                    }
                }
            }
        }
        group("Other keys") {
            ChipFlow(spacing: 6) {
                ForEach([VirtualKey.escape, VirtualKey.tab, VirtualKey.enter, VirtualKey.space, VirtualKey.backspace,
                         VirtualKey.delete, VirtualKey.insert, VirtualKey.home, VirtualKey.end, VirtualKey.pageUp,
                         VirtualKey.pageDown, VirtualKey.pause, VirtualKey.printScreen], id: \.self) { vk in
                    key(vk)
                }
            }
        }
        if allActions {
            group("Mouse") {
                ChipFlow(spacing: 6) {
                    ForEach([ControlAction.mouse(.left), .mouse(.right), .mouse(.middle), .wheel(.up), .wheel(.down)],
                            id: \.self) { action in choice(action) }
                }
            }
            group("Controller buttons") {
                ChipFlow(spacing: 6) {
                    ForEach(ControlAction.PadButton.allCases, id: \.self) { button in
                        choice(.pad(button), label: Self.padLabel(button))
                    }
                }
            }
            group("Typing") {
                choice(.keyboard, label: "Keyboard button")
            }
        }
        Text("Letters, numbers and punctuation: switch to Type it on the keyboard and press the key.")
            .font(.quicksand(13, .semibold, relativeTo: .footnote))
            .foregroundStyle(StudioColors.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.quicksand(13, .bold, relativeTo: .footnote))
                .foregroundStyle(StudioColors.secondaryInk)
            content()
        }
    }

    private func key(_ vk: Int, label: String? = nil, width: CGFloat? = nil, fill: Bool = false,
                     tinted: Bool = false) -> some View {
        Button(label ?? VirtualKey.name(vk)) { pick(.key(vk)) }
            .buttonStyle(CardChipStyle(tinted: tinted, height: 38))
            .frame(width: width)
            .frame(maxWidth: fill ? .infinity : nil)
            .accessibilityLabel(label == nil ? VirtualKey.name(vk) : "\(VirtualKey.name(vk)) arrow")
    }

    private func choice(_ action: ControlAction, label: String? = nil) -> some View {
        Button(label ?? action.name) { pick(action) }
            .buttonStyle(CardChipStyle(height: 38))
    }

    /// The D-pad's directions say so; the rest are the controller's own names.
    private static func padLabel(_ button: ControlAction.PadButton) -> String {
        switch button {
        case .up, .down, .left, .right: "D-pad \(button.name.lowercased())"
        default: button.name
        }
    }
}

/// Brings up the iPhone's keyboard and reports the first key typed, as the
/// key a US keyboard has for it.
private struct KeyCatcher: UIViewRepresentable {
    let pick: (ControlAction) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.pick = pick
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.pick = pick
    }

    final class CatcherView: UIView, UIKeyInput {
        var pick: ((ControlAction) -> Void)?
        var autocorrectionType = UITextAutocorrectionType.no
        var autocapitalizationType = UITextAutocapitalizationType.none
        var spellCheckingType = UITextSpellCheckingType.no
        var smartQuotesType = UITextSmartQuotesType.no
        var smartDashesType = UITextSmartDashesType.no
        var keyboardType = UIKeyboardType.asciiCapable

        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }

        func insertText(_ text: String) {
            guard let scalar = text.unicodeScalars.first else { return }
            if scalar == "\n" { return pick?(.key(VirtualKey.enter)) ?? () }
            if let key = VirtualKey.usKey(for: scalar) { pick?(.key(key.vk)) }
        }

        func deleteBackward() {
            pick?(.key(VirtualKey.backspace))
        }
    }
}
