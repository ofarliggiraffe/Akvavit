// SPDX-License-Identifier: GPL-3.0-or-later
//
// Typing into the game with the iPhone's keyboard (the Keyboard button).
//
// The keyboard needs a view that can become first responder in the key
// window: the app's own window (GameOverlay's window never becomes key). Each
// character goes to the engine as text, with its key on a US keyboard where
// it has one, so games that read keys get them too. The engine takes text one
// character at a time and says when it is busy; then the same character is
// tried again shortly, so nothing is lost or reordered. Backspace and Enter
// are keys. A tap on the game puts the keyboard away.

import UIKit

@MainActor
public final class TextBridge {
    public static let shared = TextBridge()

    private enum Stroke {
        case text(Unicode.Scalar)
        case key(Int)
    }

    private lazy var input = KeyboardInputView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private var waiting: [Stroke] = []
    private var retry: Timer?
    /// The engine's pause between typed characters, in milliseconds.
    private static let pace: Int32 = 10

    public var isShown: Bool { input.isFirstResponder }

    public func toggle() {
        isShown ? hide() : show()
    }

    public func show() {
        guard let window = GameLayerHost.shared.window else { return }
        if input.superview !== window { window.addSubview(input) }
        input.becomeFirstResponder()
    }

    public func hide() {
        if input.isFirstResponder { input.resignFirstResponder() }
    }

    fileprivate func type(_ text: String) {
        for scalar in text.unicodeScalars {
            waiting.append(scalar == "\n" ? .key(VirtualKey.enter) : .text(scalar))
        }
        send()
    }

    fileprivate func typeKey(_ vk: Int) {
        waiting.append(.key(vk))
        send()
    }

    private func send() {
        retry?.invalidate()
        retry = nil
        while let stroke = waiting.first {
            switch stroke {
            case .key(let vk):
                winios_post_key(Int32(vk), 1)
                winios_post_key(Int32(vk), 0)
            case .text(let scalar):
                let key = VirtualKey.usKey(for: scalar)
                guard winios_try_post_text(scalar.value, Int32(key?.vk ?? 0), key?.shift == true ? 1 : 0, Self.pace) != 0 else {
                    retry = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: false) { _ in
                        MainActor.assumeIsolated { TextBridge.shared.send() }
                    }
                    return
                }
            }
            waiting.removeFirst()
        }
    }
}

/// The view the keyboard types into. Plain typing: no corrections, no
/// capitals, no smart punctuation.
private final class KeyboardInputView: UIView, UIKeyInput {
    var autocorrectionType = UITextAutocorrectionType.no
    var autocapitalizationType = UITextAutocapitalizationType.none
    var spellCheckingType = UITextSpellCheckingType.no
    var smartQuotesType = UITextSmartQuotesType.no
    var smartDashesType = UITextSmartDashesType.no
    var smartInsertDeleteType = UITextSmartInsertDeleteType.no
    var keyboardType = UIKeyboardType.asciiCapable

    override var canBecomeFirstResponder: Bool { true }

    /// Always: Backspace reaches the game even with nothing typed here.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        TextBridge.shared.type(text)
    }

    func deleteBackward() {
        TextBridge.shared.typeKey(VirtualKey.backspace)
    }
}
