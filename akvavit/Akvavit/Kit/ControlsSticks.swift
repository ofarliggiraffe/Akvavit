// SPDX-License-Identifier: GPL-3.0-or-later
//
// Sticks in play, and the controller they drive (part of ControlsRuntime).
//
// A stick's centre is where the thumb lands (or the stick's middle); its knob
// reaches about a third of its size from there. It works as:
// - a controller stick: XInput's left or right stick, player 1;
// - W A S D or the arrow keys: held in the direction pushed (two on
//   diagonals), as the move pad does;
// - the mouse: a turning speed, faster the further it is pushed (aim).
//
// The controller (slot 0 of the engine's controller snapshot, player 1) is
// connected once a layout with controller sticks or buttons is in use (from
// before the game starts, so a game that looks for controllers once finds
// it), and stays connected while the app runs, as a real one would: a layout
// without it leaves it at rest.

import QuartzCore
import UIKit

/// The thumb on one stick.
final class StickThumb {
    let stick: ControlStick
    let finger: ObjectIdentifier
    let centre: CGPoint
    /// How far the knob goes, in points.
    let reach: CGFloat
    /// The push with the dead zone taken out: length 0 to 1, y up.
    var push = CGVector.zero
    /// Keys: the direction held, and its keys.
    var direction: Int?
    var keys: [Int] = []

    init(stick: ControlStick, finger: ObjectIdentifier, centre: CGPoint, reach: CGFloat) {
        self.stick = stick
        self.finger = finger
        self.centre = centre
        self.reach = reach
    }
}

extension ControlsRuntime {
    /// The knob's reach, as a part of the stick's size.
    public static let stickReach: CGFloat = 0.31
    /// Mouse: counts per second with the stick pushed all the way.
    private static let stickAimSpeed: CGFloat = 1200

    static func usesPad(_ layout: ControlLayout) -> Bool {
        layout.controls.contains { control in
            switch control.kind {
            case .button(let button): if case .pad = button.action { true } else { false }
            case .stick(let stick): stick.worksAs == .leftStick || stick.worksAs == .rightStick
            default: false
            }
        }
    }

    // MARK: The controller

    func connectPad() {
        guard !padConnected else { return }
        pad = winios_gamepad()
        padConnected = true
        publishPad()
        fputs("[controls] controller connected (player 1)\n", stderr)
    }

    private func publishPad() {
        guard padConnected else { return }
        var state = pad
        state.connected = 1
        winios_gamepad_set_state(0, &state)
    }

    func setPadButton(_ button: ControlAction.PadButton, down: Bool) {
        switch button {
        case .lt: pad.left_trigger = down ? 255 : 0
        case .rt: pad.right_trigger = down ? 255 : 0
        default:
            let bit = Self.padBit(button)
            pad.buttons = down ? pad.buttons | bit : pad.buttons & ~bit
        }
        publishPad()
        fputs("[controls] pad \(button.rawValue) \(down ? "down" : "up")\n", stderr)
    }

    /// XInput's XINPUT_GAMEPAD_* bits.
    private static func padBit(_ button: ControlAction.PadButton) -> UInt16 {
        switch button {
        case .up: 0x0001
        case .down: 0x0002
        case .left: 0x0004
        case .right: 0x0008
        case .start: 0x0010
        case .back: 0x0020
        case .leftStick: 0x0040
        case .rightStick: 0x0080
        case .lb: 0x0100
        case .rb: 0x0200
        case .a: 0x1000
        case .b: 0x2000
        case .x: 0x4000
        case .y: 0x8000
        case .lt, .rt: 0
        }
    }

    private static func axis(_ value: CGFloat) -> Int16 {
        Int16(clamping: Int((value * 32767).rounded()))
    }

    // MARK: Sticks

    /// False when the stick already has a thumb on it.
    func stickBegan(_ id: UUID, _ stick: ControlStick, in frame: CGRect, finger: ObjectIdentifier,
                    at point: CGPoint) -> Bool {
        guard sticks[id] == nil else { return false }
        let centre = stick.centreWhereThumbLands ? point : CGPoint(x: frame.midX, y: frame.midY)
        let reach = min(frame.width, frame.height) * Self.stickReach
        sticks[id] = StickThumb(stick: stick, finger: finger, centre: centre, reach: reach)
        state(of: id).pressed = true
        stickMoved(id, finger: finger, to: point)
        if stick.worksAs == .mouse { startMotionLink() }
        return true
    }

    func stickMoved(_ id: UUID, finger: ObjectIdentifier, to point: CGPoint) {
        guard let thumb = sticks[id], thumb.finger == finger else { return }
        var dx = (point.x - thumb.centre.x) / thumb.reach, dy = (point.y - thumb.centre.y) / thumb.reach
        let length = hypot(dx, dy)
        if length > 1 { dx /= length; dy /= length }
        state(of: id).knob = CGPoint(x: dx, y: dy)
        let pushed = min(length, 1), deadZone = CGFloat(thumb.stick.deadZone)
        let live = pushed <= deadZone ? 0 : (pushed - deadZone) / (1 - deadZone)
        let scale = pushed > 0 ? live / pushed : 0
        thumb.push = CGVector(dx: dx * scale, dy: -dy * scale)
        switch thumb.stick.worksAs {
        case .leftStick:
            pad.lx = Self.axis(thumb.push.dx)
            pad.ly = Self.axis(thumb.push.dy)
            publishPad()
        case .rightStick:
            pad.rx = Self.axis(thumb.push.dx)
            pad.ry = Self.axis(thumb.push.dy)
            publishPad()
        case .wasd, .arrows:
            let direction = Self.direction(dx, -dy, held: thumb.direction, enter: deadZone, leave: deadZone * 0.7)
            guard direction != thumb.direction else { return }
            thumb.direction = direction
            let keys = thumb.stick.worksAs == .wasd ? Self.wasd : Self.arrows
            setKeys(&thumb.keys, direction.map { keys[$0] } ?? [])
        case .mouse:
            break   // turned into motion each frame (stickAim)
        }
    }

    func stickEnded(_ id: UUID, finger: ObjectIdentifier) {
        guard let thumb = sticks[id], thumb.finger == finger else { return }
        sticks[id] = nil
        let state = state(of: id)
        state.pressed = false
        state.knob = .zero
        switch thumb.stick.worksAs {
        case .leftStick:
            pad.lx = 0
            pad.ly = 0
            publishPad()
        case .rightStick:
            pad.rx = 0
            pad.ry = 0
            publishPad()
        case .wasd, .arrows:
            setKeys(&thumb.keys, [])
        case .mouse:
            break
        }
    }

    /// Ends every stick's touch and centres the controller; keys held by
    /// sticks are let go with the rest.
    func stopSticks() {
        sticks = [:]
        guard padConnected else { return }
        pad = winios_gamepad()
        publishPad()
    }

    var hasAimingSticks: Bool { sticks.values.contains { $0.stick.worksAs == .mouse } }

    /// Mouse sticks: their turning for `seconds`, added to the aim motion.
    func stickAim(_ seconds: CFTimeInterval) {
        for thumb in sticks.values where thumb.stick.worksAs == .mouse {
            aim.dx += thumb.push.dx * Self.stickAimSpeed * seconds
            aim.dy -= thumb.push.dy * Self.stickAimSpeed * seconds
        }
    }
}
