// SPDX-License-Identifier: GPL-3.0-or-later
//
// On-screen controls: names for every key, a label of the user's own, sticky Ctrl, Shift
// and Alt buttons (Ctrl+1 and such, for strategy games), and deleting a control from its
// mapping panel.
//
// Madeira's ControlAction.keyLabel names only a few keys and shows the rest in hex (F1
// was "70"); AkvavitKeyNames names the rest, as the mapping panel's catalogues do.
// TouchControl.customLabel (optional, so older layouts still load) replaces the name on
// the button. A Ctrl, Shift or Alt button can be sticky (TouchControl.sticky): a tap
// presses its key and keeps it down, and the next key button's release lets it go
// (AkvavitStickyKeys), as Madeira's on-screen keyboard does with its modifiers. The key goes
// down at the tap, well before the other one: sending both at once (an earlier try) did
// not reach Age of Empires II HD. Mouse buttons leave it down, for Ctrl- or Shift-clicks;
// a second tap releases it. Only for touch: a controller button bound to the control
// presses its key as an ordinary one.
// MappingPanel gets a row with a label field, the sticky toggle and a delete button;
// the delete badge on the button itself is gone, since it sat where a drag starts.
//
// The controls window is never key (TouchControlsHost), and only the key window gets
// typing, so the label field makes it key while it is edited and gives it back after.
//
// Hooks in Madeira's ContentView.swift, marked "Akvavit:": ControlAction.keyLabel,
// TouchControl, TouchControlButton and MappingPanel.

import SwiftUI
import UIKit

enum AkvavitKeyNames {
    /// The keys ControlAction.keyLabel leaves in hex.
    static func label(_ vk: Int32) -> String? {
        switch vk {
        case 0x70...0x87: return "F\(vk - 0x6F)"          // F1-F24
        case 0x60...0x69: return "N\(vk - 0x60)"          // numeric keypad
        case 0x6A: return "N*"
        case 0x6B: return "N+"
        case 0x6D: return "N−"
        case 0x6E: return "N."
        case 0x6F: return "N/"
        case 0x08: return "Bksp"
        case 0x2E: return "Del"
        case 0x2D: return "Ins"
        case 0x24: return "Home"
        case 0x23: return "End"
        case 0x21: return "PgUp"
        case 0x22: return "PgDn"
        case 0x14: return "Caps"
        case 0x13: return "Pause"
        case 0x2C: return "PrtSc"
        case 0x5B, 0x5C: return "Win"
        case 0xA0, 0xA1: return "Shift"
        case 0xA2, 0xA3: return "Ctrl"
        case 0xA4, 0xA5: return "Alt"
        case 0xBA: return ";"
        case 0xBB: return "="
        case 0xBC: return ","
        case 0xBD: return "-"
        case 0xBE: return "."
        case 0xBF: return "/"
        case 0xC0: return "`"
        case 0xDB: return "["
        case 0xDC: return "\\"
        case 0xDD: return "]"
        case 0xDE: return "'"
        default: return nil
        }
    }
}

/// Sticky modifier buttons: the keys a tap has pressed and the next key will let go.
final class AkvavitStickyKeys: ObservableObject {
    static let shared = AkvavitStickyKeys()
    /// Down now, in the order they were tapped.
    @Published private(set) var latched: [Int32] = []

    static func isModifier(_ vk: Int32) -> Bool {
        [0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5].contains(vk)
    }

    /// TouchControlButton.press for a key.
    func press(_ vk: Int32, sticky: Bool, down: Bool) {
        if sticky && Self.isModifier(vk) {
            guard down else { return }
            if let i = latched.firstIndex(of: vk) {
                latched.remove(at: i)
                winios_post_key(vk, 0)
            } else {
                latched.append(vk)
                winios_post_key(vk, 1)
            }
            return
        }
        winios_post_key(vk, down ? 1 : 0)
        if !down && !Self.isModifier(vk) { release() }
    }

    /// Lets every latched key go (after the next key, and at the end of a session).
    func release() {
        for vk in latched.reversed() { winios_post_key(vk, 0) }
        latched = []
    }
}

/// TouchControlButton's ring while its sticky key is down.
struct AkvavitStickyMark: View {
    let control: TouchControl
    let shape: AnyShape
    @ObservedObject private var keys = AkvavitStickyKeys.shared

    var body: some View {
        if control.sticky == true, case .key(let vk) = control.action, keys.latched.contains(vk) {
            shape.fill(Color.accentColor.opacity(0.35))
                .overlay(shape.stroke(Color.accentColor, lineWidth: 3))
                .allowsHitTesting(false)
        }
    }
}

extension TouchControl {
    /// What the button shows: the user's own label, or the action's name.
    var displayLabel: String {
        if let customLabel, !customLabel.trimmingCharacters(in: .whitespaces).isEmpty { return customLabel }
        return action.label
    }
}

/// MappingPanel's row: the control's label, and deleting it.
struct AkvavitControlLabelRow: View {
    let control: TouchControl
    @ObservedObject private var m = TouchControlsModel.shared
    @FocusState private var typing: Bool
    @State private var previousKey: UIWindow?

    static let maxLength = 12

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: label,
                      prompt: Text("Label: \(defaultLabel)").foregroundStyle(.white.opacity(0.38)))
                .focused($typing)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { typing = false }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
            if case .key(let vk) = control.action, AkvavitStickyKeys.isModifier(vk) {
                let on = control.sticky == true
                Button { toggleSticky() } label: {
                    Text("Sticky")
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.5))
                        .padding(.horizontal, 7)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(on ? Color.accentColor.opacity(0.7) : .white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sticky: a tap keeps the key down until the next key")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                typing = false
                AkvavitStickyKeys.shared.release()
                m.controls.removeAll { $0.id == control.id }
                m.selected = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(control.locked == true ? 0.3 : 0.8)))
            }
            .buttonStyle(.plain)
            .disabled(control.locked == true)
            .accessibilityLabel("Delete control")
        }
        .onChange(of: typing) { _, now in now ? takeKeyboard() : giveBackKeyboard() }
        .onDisappear { giveBackKeyboard() }
    }

    /// The name the button shows without a label of its own.
    private var defaultLabel: String { control.action.label }

    /// Sticky or hold-to-press; a key latched by this button is let go first.
    private func toggleSticky() {
        guard let i = m.index(of: control.id) else { return }
        AkvavitStickyKeys.shared.release()
        m.controls[i].sticky = m.controls[i].sticky == true ? nil : true
    }

    /// The custom label; empty clears it.
    private var label: Binding<String> {
        Binding(get: { control.customLabel ?? "" }, set: { new in
            guard let i = m.index(of: control.id) else { return }
            let text = String(new.prefix(Self.maxLength))
            m.controls[i].customLabel = text.isEmpty ? nil : text
        })
    }

    private static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }

    private func takeKeyboard() {
        guard previousKey == nil, let controls = Self.windows.first(where: { $0 is ControlsWindow }) else { return }
        previousKey = Self.windows.first { $0.isKeyWindow && $0 !== controls }
        controls.makeKey()
    }

    private func giveBackKeyboard() {
        previousKey?.makeKey()
        previousKey = nil
    }
}
