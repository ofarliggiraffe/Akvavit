// SPDX-License-Identifier: GPL-3.0-or-later
//
// The built-in control layouts (the design canvas's "Controls" boards). They
// can't be changed; "Make a copy" gives an exact copy to edit. Sizes fit the
// smallest iPhone in landscape (667 × 375 points) and keep their place on
// larger displays.

import Foundation

public enum BuiltInLayouts {
    public static let all = [touchAsMouse, strategyTrackpad, shooterController, shooterTrackpads]

    /// No controls: a finger on the game is the mouse.
    public static let touchAsMouse = ControlLayout(id: "builtin.touch", name: "Touch as mouse", controls: [])

    public static let strategyTrackpad = ControlLayout(
        id: "builtin.strategy", name: "Strategy trackpad",
        controls: [
            Control(.keyRow(.numbers), Placement(.center, 0, .start, 12, width: 452, height: 32)),
            Control(.button(ControlButton(.key(VirtualKey.ctrl), whenTapped: .sticky, shape: .rounded, colour: .lilac)),
                    Placement(.start, 76, .end, 128, width: 80, height: 80)),
            Control(.button(ControlButton(.mouse(.left))), Placement(.start, 24, .end, 24, width: 84, height: 84)),
            Control(.button(ControlButton(.mouse(.right))), Placement(.start, 126, .end, 24, width: 84, height: 84)),
            Control(.trackpad(ControlTrackpad(.mouse)), Placement(.end, 24, .end, 24, width: 300, height: 280)),
        ])

    public static let shooterController = ControlLayout(
        id: "builtin.shooterController", name: "Shooter, controller",
        controls: [
            Control(.stick(ControlStick(.leftStick)), Placement(.start, 40, .end, 24, width: 150, height: 150)),
            Control(.stick(ControlStick(.rightStick)), Placement(.end, 210, .end, 24, width: 130, height: 130)),
            pad(.y, colour: .yellow, .end, 78, .end, 132),
            pad(.x, colour: .blue, .end, 132, .end, 78),
            pad(.b, colour: .red, .end, 24, .end, 78),
            pad(.a, colour: .green, .end, 78, .end, 24),
            shoulder(.lt, .start, 12), shoulder(.lb, .start, 60),
            shoulder(.rt, .end, 12), shoulder(.rb, .end, 60),
            Control(.button(ControlButton(.pad(.back), shape: .rounded)), Placement(.center, -44, .start, 12, width: 72, height: 36)),
            Control(.button(ControlButton(.pad(.start), shape: .rounded)), Placement(.center, 44, .start, 12, width: 72, height: 36)),
        ],
        gameTouch: .off)

    public static let shooterTrackpads = ControlLayout(
        id: "builtin.shooterTrackpads", name: "Shooter, trackpads",
        controls: [
            // Fire, Jump and Crouch lie over the aim pad; buttons come first.
            Control(.trackpad(ControlTrackpad(.move)), Placement(.start, 16, .end, 16, width: 300, height: 340)),
            Control(.trackpad(ControlTrackpad(.aim)), Placement(.end, 16, .end, 16, width: 340, height: 300)),
            Control(.button(ControlButton(.mouse(.left), label: "Fire", colour: .red)),
                    Placement(.end, 24, .end, 16, width: 80, height: 80)),
            Control(.button(ControlButton(.key(VirtualKey.space), label: "Jump")),
                    Placement(.end, 118, .end, 16, width: 64, height: 64)),
            Control(.button(ControlButton(.key(VirtualKey.ctrl), label: "Crouch", shape: .rounded)),
                    Placement(.end, 196, .end, 16, width: 64, height: 64)),
        ],
        gameTouch: .off)

    private static func pad(_ button: ControlAction.PadButton, colour: ControlButton.Colour,
                            _ h: Placement.Anchor, _ x: Double, _ v: Placement.Anchor, _ y: Double) -> Control {
        Control(.button(ControlButton(.pad(button), colour: colour)), Placement(h, x, v, y, width: 54, height: 54))
    }

    private static func shoulder(_ button: ControlAction.PadButton, _ side: Placement.Anchor, _ top: Double) -> Control {
        Control(.button(ControlButton(.pad(button), shape: .rounded)), Placement(side, 24, .start, top, width: 80, height: 40))
    }
}
