// SPDX-License-Identifier: GPL-3.0-or-later
//
// On-screen controls in play: which layout is in use, which control each
// finger is on, and what goes to the game.
//
// Each touch belongs to the control it began on for its whole life
// (ControlsInputView, in GameOverlay's window); fingers elsewhere go to the
// game as the mouse, unless the layout turns that off. What controls send is
// counted per action, so two controls with the same key (or a finger and a
// sticky button) give one key-down and one key-up.

import Observation
import QuartzCore
import UIKit

/// What a control looks like right now, observed by its face alone.
@MainActor @Observable
public final class ControlState {
    /// A finger is on it.
    public internal(set) var pressed = false
    /// Down without a finger on it (Hold or Sticky).
    public internal(set) var latched = false
    /// For a key row: the key a finger is on.
    public internal(set) var pressedKey: Int?
    /// For a stick: where the knob is, as a part of its reach (-1 to 1 each
    /// way, y down).
    public internal(set) var knob = CGPoint.zero
}

@MainActor @Observable
public final class ControlsRuntime {
    public static let shared = ControlsRuntime()

    /// The layout over the game; nil until one is chosen.
    public private(set) var layout: ControlLayout?
    /// The controls' area (the whole display), in points.
    public private(set) var area = CGRect.zero

    @ObservationIgnored private var states: [UUID: ControlState] = [:]
    @ObservationIgnored private var downCounts: [ControlAction: Int] = [:]
    /// Sticky controls that are down, with what they hold.
    @ObservationIgnored private var stickies: [UUID: ControlAction] = [:]
    /// Advances when everything is let go, so touches from before change nothing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private lazy var haptics = UIImpactFeedbackGenerator(style: .light)
    /// Trackpads with fingers on them, and motion not sent yet
    /// (ControlsTrackpads.swift).
    @ObservationIgnored var trackpads: [UUID: TrackpadFingers] = [:]
    @ObservationIgnored var cursor: CGPoint?
    @ObservationIgnored var cursorMoved = false
    @ObservationIgnored var aim = CGVector.zero
    @ObservationIgnored var motionLink: CADisplayLink?
    /// Sticks with a thumb on them, and the controller they drive
    /// (ControlsSticks.swift).
    @ObservationIgnored var sticks: [UUID: StickThumb] = [:]
    @ObservationIgnored var pad = winios_gamepad()
    @ObservationIgnored var padConnected = false

    /// Games see a press at least this long, however quick the tap.
    private static let shortestPress: CFTimeInterval = 0.05

    private init() {
        // Nothing stays down while the app is away (a call, Control Center).
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.releaseAll() }
            })
    }

    /// Whether a finger on the game is the mouse.
    public var touchAsMouse: Bool { layout?.gameTouch != .off }

    public func use(_ layout: ControlLayout?) {
        guard layout != self.layout else { return }
        releaseAll()
        states = [:]
        self.layout = layout
        fputs("[controls] layout \(layout?.name ?? "none")\n", stderr)
        if let layout, Self.usesPad(layout) { connectPad() }
    }

    public func state(of id: UUID) -> ControlState {
        if let state = states[id] { return state }
        let state = ControlState()
        states[id] = state
        return state
    }

    /// Lets go of everything the controls hold down.
    public func releaseAll() {
        stopTrackpads()
        stopSticks()
        for action in downCounts.keys { send(action, down: false) }
        downCounts = [:]
        stickies = [:]
        generation += 1
        for state in states.values {
            state.pressed = false
            state.latched = false
            state.pressedKey = nil
            state.knob = .zero
        }
    }

    func setArea(_ area: CGRect) {
        guard self.area != area else { return }
        self.area = area
        fputs("[controls] area \(Int(area.width))x\(Int(area.height))\n", stderr)
    }

    /// A click on the game has been let go: sticky keys go up after it.
    func mouseButtonReleased() {
        releaseStickies()
    }

    /// Touch on the game moved the cursor to (x, y) Windows pixels: the
    /// mouse trackpad goes on from there.
    func pointerMoved(toX x: Int32, y: Int32) {
        cursor = CGPoint(x: Int(x), y: Int(y))
    }

    // MARK: Touches

    struct Touch {
        enum Role {
            /// A button or key: what the touch holds, and how.
            case press(ControlAction, PressBehaviour)
            case trackpad
            case stick
        }

        let control: UUID
        let role: Role
        let generation: Int
        let began: CFTimeInterval
    }

    /// The control at `point` that takes touches, with the key for a key row.
    /// Buttons and keys over a trackpad come first.
    func control(at point: CGPoint) -> (control: Control, key: Int?)? {
        guard let layout else { return nil }
        let hits = layout.controls.reversed().filter { $0.placement.frame(in: area).contains(point) }
        for control in hits {
            switch control.kind {
            case .button, .stick:
                return (control, nil)
            case .keyRow(let row):
                if let key = row.keyIndex(at: point.x, in: control.placement.frame(in: area)) { return (control, key) }
            default:
                continue
            }
        }
        return hits.first { if case .trackpad = $0.kind { true } else { false } }.map { ($0, nil) }
    }

    /// A finger landed on `control` (`finger` names it until it lifts).
    func began(_ control: Control, key: Int?, finger: ObjectIdentifier, at point: CGPoint) -> Touch? {
        tap(for: control)
        let state = state(of: control.id)
        let action: ControlAction, behaviour: PressBehaviour
        switch control.kind {
        case .trackpad(let pad):
            trackpadBegan(control.id, pad, finger: finger, at: point)
            return Touch(control: control.id, role: .trackpad, generation: generation, began: CACurrentMediaTime())
        case .stick(let stick):
            guard stickBegan(control.id, stick, in: control.placement.frame(in: area), finger: finger, at: point)
            else { return nil }
            return Touch(control: control.id, role: .stick, generation: generation, began: CACurrentMediaTime())
        case .button(let button):
            (action, behaviour) = (button.action, button.whenTapped)
        case .keyRow(let row):
            guard let key, row.keys.indices.contains(key) else { return nil }
            (action, behaviour) = (.key(row.keys[key]), .press)
            state.pressedKey = key
        default:
            return nil
        }
        state.pressed = true
        switch behaviour {
        case .press:
            press(action)
        case .hold:
            if state.latched {
                state.latched = false
                release(action)
                releaseStickies()
            } else {
                state.latched = true
                press(action)
            }
        case .sticky:
            if stickies.removeValue(forKey: control.id) != nil {
                state.latched = false
                release(action)
            } else {
                stickies[control.id] = action
                state.latched = true
                press(action)
            }
        }
        return Touch(control: control.id, role: .press(action, behaviour),
                     generation: generation, began: CACurrentMediaTime())
    }

    func moved(_ touch: Touch, finger: ObjectIdentifier, to point: CGPoint) {
        switch touch.role {
        case .trackpad: trackpadMoved(touch.control, finger: finger, to: point)
        case .stick: stickMoved(touch.control, finger: finger, to: point)
        case .press: break
        }
    }

    func ended(_ touch: Touch, finger: ObjectIdentifier) {
        switch touch.role {
        case .trackpad: return trackpadEnded(touch.control, finger: finger)
        case .stick: return stickEnded(touch.control, finger: finger)
        case .press(_, let behaviour):
            let state = state(of: touch.control)
            state.pressed = false
            state.pressedKey = nil
            guard behaviour == .press, touch.generation == generation else { return }
        }
        let wait = Self.shortestPress - (CACurrentMediaTime() - touch.began)
        guard wait > 0 else { return finishPress(touch) }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated { self?.finishPress(touch) }
        }
    }

    private func finishPress(_ touch: Touch) {
        guard touch.generation == generation, case .press(let action, _) = touch.role else { return }
        release(action)
        releaseStickies()
    }

    /// A light tap under the finger: only when the control's own switch,
    /// its layout's and the Controls tab's are all on.
    private func tap(for control: Control) {
        guard control.haptics, layout?.haptics == true, ControlLayoutStore.shared.haptics else { return }
        haptics.impactOccurred()
    }

    // MARK: Sending

    func releaseStickies() {
        guard !stickies.isEmpty else { return }
        for (id, action) in stickies {
            release(action)
            states[id]?.latched = false
        }
        stickies = [:]
    }

    func press(_ action: ControlAction) {
        let count = downCounts[action, default: 0]
        downCounts[action] = count + 1
        if count == 0 { send(action, down: true) }
    }

    func release(_ action: ControlAction) {
        guard let count = downCounts[action] else { return }
        if count > 1 {
            downCounts[action] = count - 1
        } else {
            downCounts[action] = nil
            send(action, down: false)
        }
    }

    /// Mouse event flags of Windows' SendInput (MOUSEEVENTF_*). Buttons and
    /// the wheel without MOVE carry no position: the cursor stays put.
    private func send(_ action: ControlAction, down: Bool) {
        switch action {
        case .key(let vk):
            winios_post_key(Int32(vk), down ? 1 : 0)
            fputs(String(format: "[controls] key 0x%02X %@\n", vk, down ? "down" : "up"), stderr)
        case .mouse(let button):
            flushMotion()   // clicks where a trackpad has just put the cursor
            let flags: UInt32 = switch button {
            case .left: down ? 0x0002 : 0x0004
            case .right: down ? 0x0008 : 0x0010
            case .middle: down ? 0x0020 : 0x0040
            }
            winios_pointer(0, 0, flags, 0)
            fputs("[controls] \(button.rawValue) \(down ? "down" : "up")\n", stderr)
        case .wheel(let wheel):
            guard down else { return }
            winios_pointer(0, 0, 0x0800, UInt32(bitPattern: wheel == .up ? 120 : -120))
        case .pad(let button):
            setPadButton(button, down: down)
        case .keyboard:
            if down { TextBridge.shared.toggle() }
        }
    }
}

/// The view over the game that takes the touches on controls. GameOverlay
/// sends it only touches that begin on a control (`owns`).
public final class ControlsInputView: UIView {
    private let runtime = ControlsRuntime.shared
    private var touchesOnControls: [ObjectIdentifier: ControlsRuntime.Touch] = [:]

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// While the loading screen covers the game, touches go past to it.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        StartProgress.shared.covers ? nil : super.hitTest(point, with: event)
    }

    /// Whether a touch at `point` (in this view) is on a control.
    public func owns(_ point: CGPoint) -> Bool {
        !StartProgress.shared.covers && runtime.control(at: point) != nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        runtime.setArea(bounds)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self), finger = ObjectIdentifier(touch)
            guard let hit = runtime.control(at: point),
                  let record = runtime.began(hit.control, key: hit.key, finger: finger, at: point) else { continue }
            touchesOnControls[finger] = record
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let finger = ObjectIdentifier(touch)
            if let record = touchesOnControls[finger] { runtime.moved(record, finger: finger, to: touch.location(in: self)) }
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let finger = ObjectIdentifier(touch)
            if let record = touchesOnControls.removeValue(forKey: finger) { runtime.ended(record, finger: finger) }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
