// SPDX-License-Identifier: GPL-3.0-or-later
//
// Trackpads in play (part of ControlsRuntime).
//
// - Mouse: the finger moves the Windows cursor from where it is (it starts in
//   the middle).
// - Aim: the finger moves the mouse without a position, as a real mouse does,
//   for games that hide the cursor and turn the view with it.
//
// Trackpads only move (a tap clicking got in the way of drawing boxes):
// clicks are buttons.
// - Move: W, A, S and D, held in the direction the finger has moved from
//   where it landed (two keys on diagonals), all let go when it lifts.
//
// Motion is gathered and sent once per display frame: the engine's input
// queue drops new events when it is full, and a lost key-up would leave a key
// down.

import QuartzCore
import UIKit

/// The fingers on one trackpad.
final class TrackpadFingers {
    let pad: ControlTrackpad
    var points: [ObjectIdentifier: CGPoint] = [:]
    /// The finger that moves things (the first one down).
    var mover: ObjectIdentifier?
    /// Move: where the finger landed, the direction held (in eighths of a
    /// turn from the right, anticlockwise), and the keys held for it.
    var origin = CGPoint.zero
    var direction: Int?
    var keys: [Int] = []

    init(pad: ControlTrackpad) { self.pad = pad }
}

extension ControlsRuntime {
    /// Mouse: Windows pixels per point of finger travel, at speed 1, over the
    /// picture's own scale.
    private static let mouseGain: CGFloat = 2
    /// Aim: mouse counts per point of finger travel, at speed 1.
    private static let aimGain: CGFloat = 6
    /// Move: how far the finger goes before a direction counts, and how close
    /// to where it landed it has to come back to let go, at speed 1 (a higher
    /// speed takes less).
    private static let moveDeadZone: CGFloat = 14
    private static let moveRelease: CGFloat = 10
    /// The keys for each direction, right first, anticlockwise.
    static let wasd = keys(up: 0x57, left: 0x41, down: 0x53, right: 0x44)
    static let arrows = keys(up: VirtualKey.up, left: VirtualKey.left, down: VirtualKey.down, right: VirtualKey.right)

    private static func keys(up: Int, left: Int, down: Int, right: Int) -> [[Int]] {
        [[right], [up, right], [up], [up, left], [left], [down, left], [down], [down, right]]
    }

    func trackpadBegan(_ id: UUID, _ pad: ControlTrackpad, finger: ObjectIdentifier, at point: CGPoint) {
        let fingers = trackpads[id] ?? TrackpadFingers(pad: pad)
        trackpads[id] = fingers
        fingers.points[finger] = point
        if fingers.mover == nil {
            fingers.mover = finger
            fingers.origin = point
        }
        state(of: id).pressed = true
        startMotionLink()
    }

    func trackpadMoved(_ id: UUID, finger: ObjectIdentifier, to point: CGPoint) {
        guard let fingers = trackpads[id], let last = fingers.points[finger] else { return }
        fingers.points[finger] = point
        let dx = point.x - last.x, dy = point.y - last.y
        guard finger == fingers.mover else { return }
        let speed = CGFloat(fingers.pad.speed)
        switch fingers.pad.mode {
        case .mouse where fingers.points.count == 1:
            moveCursor(dx * speed, dy * speed)
        case .aim where fingers.points.count == 1:
            aim.dx += dx * speed * Self.aimGain
            aim.dy += dy * speed * Self.aimGain
        case .move:
            steer(fingers, to: point)
        default:
            break
        }
    }

    func trackpadEnded(_ id: UUID, finger: ObjectIdentifier) {
        guard let fingers = trackpads[id], fingers.points.removeValue(forKey: finger) != nil else { return }
        if fingers.mover == finger {
            fingers.mover = fingers.points.keys.first
            if fingers.pad.mode == .move {
                // Another finger takes over, from where it is.
                setKeys(&fingers.keys, [])
                fingers.direction = nil
                if let mover = fingers.mover, let point = fingers.points[mover] { fingers.origin = point }
            }
        }
        guard fingers.points.isEmpty else { return }
        trackpads[id] = nil
        state(of: id).pressed = false
    }

    /// Ends every trackpad's touches; the keys they hold are let go with the rest.
    func stopTrackpads() {
        motionLink?.invalidate()
        motionLink = nil
        trackpads = [:]
        cursorMoved = false
        aim = .zero
    }

    /// Sends the motion gathered since the last frame.
    func flushMotion() {
        if cursorMoved, let cursor {
            // MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, in Windows pixels.
            winios_pointer(Int32(cursor.x), Int32(cursor.y), 0x8001, 0)
            cursorMoved = false
        }
        let dx = aim.dx.rounded(.towardZero), dy = aim.dy.rounded(.towardZero)
        if dx != 0 || dy != 0 {
            // MOUSEEVENTF_MOVE alone: a relative move.
            winios_pointer(Int32(dx), Int32(dy), 0x0001, 0)
            aim.dx -= dx
            aim.dy -= dy
        }
    }

    fileprivate func motionTick(_ seconds: CFTimeInterval) {
        stickAim(seconds)
        flushMotion()
        guard trackpads.isEmpty, !hasAimingSticks else { return }
        motionLink?.invalidate()
        motionLink = nil
        aim = .zero
    }

    func startMotionLink() {
        guard motionLink == nil else { return }
        let link = CADisplayLink(target: MotionTicker(), selector: #selector(MotionTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        motionLink = link
    }

    /// Where the cursor can go: the game's window, or Windows' whole screen.
    private static func pointerArea() -> CGRect {
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        if Session.shared.config?.isDesktop != true, winios_game_client_rect(&x, &y, &w, &h) != 0, w > 0, h > 0 {
            return CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
        }
        winios_screen_size(&w, &h)
        return w > 0 && h > 0 ? CGRect(x: 0, y: 0, width: Int(w), height: Int(h)) : CGRect(x: 0, y: 0, width: 1024, height: 768)
    }

    private func moveCursor(_ dx: CGFloat, _ dy: CGFloat) {
        let area = Self.pointerArea()
        let gain = area.height / max(self.area.height, 1) * Self.mouseGain
        var point = cursor ?? CGPoint(x: area.midX, y: area.midY)
        point.x = min(max(point.x + dx * gain, area.minX), area.maxX - 1)
        point.y = min(max(point.y + dy * gain, area.minY), area.maxY - 1)
        cursor = point
        cursorMoved = true
    }

    /// Move: the direction from where the finger landed.
    private func steer(_ fingers: TrackpadFingers, to point: CGPoint) {
        let speed = CGFloat(max(fingers.pad.speed, 0.25))
        let direction = Self.direction(point.x - fingers.origin.x, fingers.origin.y - point.y, held: fingers.direction,
                                       enter: Self.moveDeadZone / speed, leave: Self.moveRelease / speed)
        guard direction != fingers.direction else { return }
        fingers.direction = direction
        setKeys(&fingers.keys, direction.map { Self.wasd[$0] } ?? [])
    }

    /// The direction of (dx, dy), y up, in eighths of a turn from the right,
    /// anticlockwise. None while shorter than `enter` (`leave` once one is
    /// held). A held direction stays until the push is clearly in the next one.
    static func direction(_ dx: CGFloat, _ dy: CGFloat, held: Int?, enter: CGFloat, leave: CGFloat) -> Int? {
        guard hypot(dx, dy) >= (held == nil ? enter : leave) else { return nil }
        let eighth = CGFloat.pi / 4
        let angle = atan2(dy, dx)
        let nearest = (Int((angle / eighth).rounded()) + 8) % 8
        guard let held else { return nearest }
        var off = abs(angle - CGFloat(held) * eighth).truncatingRemainder(dividingBy: 2 * .pi)
        if off > .pi { off = 2 * .pi - off }
        return off > eighth / 2 + 0.12 ? nearest : held
    }

    /// Holds `keys` instead of `held`: lets go of the ones no longer wanted.
    func setKeys(_ held: inout [Int], _ keys: [Int]) {
        for key in held where !keys.contains(key) { release(.key(key)) }
        for key in keys where !held.contains(key) { press(.key(key)) }
        held = keys
    }
}

/// CADisplayLink's target (it keeps it).
private final class MotionTicker: NSObject {
    @objc func tick(_ link: CADisplayLink) {
        let seconds = max(link.targetTimestamp - link.timestamp, 0)
        MainActor.assumeIsolated { ControlsRuntime.shared.motionTick(seconds) }
    }
}
