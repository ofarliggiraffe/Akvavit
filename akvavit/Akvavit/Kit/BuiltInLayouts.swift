// SPDX-License-Identifier: GPL-3.0-or-later
//
// The built-in control layouts (the design canvas's "Controls" boards), as the
// app has them; your changes are kept over them (ControlLayoutStore), and
// Restore defaults brings these back. Sizes fit the
// smallest iPhone in landscape (667 × 375 points) and keep their place on
// larger displays; "Shooter, controller" is the user's own, made on the Duo,
// and crowds the smallest phones (its sticks are 176 points). Button and stick sizes sit on the studio's Size notches
// (StudioPanels' PanelValues), so the slider steps evenly from the start.

import Foundation

public enum BuiltInLayouts {
    public static let all = [touchAsMouse, strategyTrackpad, shooterController, shooterTrackpads]

    /// The layout a game starts with until its Game settings choose another.
    public static var gameDefault: ControlLayout { touchAsMouse }

    /// No controls: a finger on the game is the mouse.
    public static let touchAsMouse = ControlLayout(id: "builtin.touch", name: "Touch as mouse", controls: [])

    public static let strategyTrackpad = ControlLayout(
        id: "builtin.strategy", name: "Strategy trackpad",
        controls: [
            Control(.keyRow(.numbers), Placement(.center, 0, .start, 12, width: 452, height: 32)),
            Control(.button(ControlButton(.key(VirtualKey.ctrl), whenTapped: .sticky, shape: .rounded, colour: .lilac)),
                    Placement(.start, 76, .end, 128, width: 80, height: 80)),
            Control(.button(ControlButton(.mouse(.left))), Placement(.start, 24, .end, 24, width: 80, height: 80)),
            Control(.button(ControlButton(.mouse(.right))), Placement(.start, 122, .end, 24, width: 80, height: 80)),
            Control(.trackpad(ControlTrackpad(.mouse)), Placement(.end, 24, .end, 24, width: 300, height: 280)),
        ])

    public static let shooterController = ControlLayout(
        id: "builtin.shooterController", name: "Shooter, controller",
        controls: [
            // The user's own arrangement (2026-11-02, made in the studio on the
            // Duo's inner display): the sticks in the bottom corners, the same
            // size; the coloured buttons above the right stick (anchored to the
            // bottom, so they stay above it on shorter displays); the shoulder
            // buttons in the top corners; Back and Start between the sticks.
            Control(.stick(ControlStick(.leftStick)), Placement(.start, 40, .end, 24, width: 176, height: 176)),
            Control(.stick(ControlStick(.rightStick)), Placement(.end, 33.5, .end, 24, width: 176, height: 176)),
            pad(.y, colour: .yellow, .end, 83.5, .end, 314.5),
            pad(.x, colour: .blue, .end, 133.5, .end, 264.5),
            pad(.b, colour: .red, .end, 33.5, .end, 264.5),
            pad(.a, colour: .green, .end, 83.5, .end, 214.5),
            shoulder(.lt, .start, 40, 20), shoulder(.lb, .start, 40, 80),
            shoulder(.rt, .end, 43.5, 22.5), shoulder(.rb, .end, 43.5, 80),
            Control(.button(ControlButton(.pad(.back), shape: .rounded)), Placement(.center, -48, .end, 24, width: 80, height: 40)),
            Control(.button(ControlButton(.pad(.start), shape: .rounded)), Placement(.center, 48, .end, 24, width: 80, height: 40)),
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
                    Placement(.end, 118, .end, 16, width: 60, height: 60)),
            Control(.button(ControlButton(.key(VirtualKey.ctrl), label: "Crouch", shape: .rounded)),
                    Placement(.end, 192, .end, 16, width: 60, height: 60)),
        ],
        gameTouch: .off)

    private static func pad(_ button: ControlAction.PadButton, colour: ControlButton.Colour,
                            _ h: Placement.Anchor, _ x: Double, _ v: Placement.Anchor, _ y: Double) -> Control {
        Control(.button(ControlButton(.pad(button), colour: colour)), Placement(h, x, v, y, width: 50, height: 50))
    }

    private static func shoulder(_ button: ControlAction.PadButton, _ side: Placement.Anchor, _ x: Double,
                                 _ top: Double) -> Control {
        Control(.button(ControlButton(.pad(button), shape: .rounded)), Placement(side, x, .start, top, width: 80, height: 40))
    }
}
