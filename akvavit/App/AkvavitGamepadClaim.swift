// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeps a game controller's input away from UIKit's focus navigation, as Madeira's
// ClaimGamepadEvents does, but on the window instead of around the app's content.
//
// ClaimGamepadEvents uses SwiftUI's handlesGameControllerEvents, which wraps the
// content in an interaction view sized to the safe area. UIKit delivers a tap only
// to a view inside all of its ancestors, so the toolbar and tab bar that iOS draws
// outside the safe area could be seen but not tapped. On the iPhone Duo the safe
// area leaves out a column on the right, where iOS puts both bars (found with a
// hit-test probe: the wrapper was 382 x 644 on the 466 x 678 outer display).
//
// GamepadEventClaim (Madeira) attaches the same GCEventInteraction to a view; on
// the window it covers every view in it and wraps none. MadeiraApp uses this
// instead of ClaimGamepadEvents (patches/).

import SwiftUI
import UIKit

struct AkvavitGamepadClaim: UIViewRepresentable {
    func makeUIView(context: Context) -> Installer {
        let view = Installer()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Installer, context: Context) {}

    final class Installer: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { GamepadEventClaim.install(on: window) }
        }
    }
}
