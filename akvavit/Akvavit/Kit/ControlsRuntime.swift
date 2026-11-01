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
}

@MainActor @Observable
public final class ControlsRuntime {
    public static let shared = ControlsRuntime()

    /// The layout over the game; nil until one is chosen.
    public private(set) var layout: ControlLayout?
    /// The controls' area and the display's safe area in it, in points.
    public private(set) var bounds = CGRect.zero
    public private(set) var safeArea = CGRect.zero

    @ObservationIgnored private var states: [UUID: ControlState] = [:]
    @ObservationIgnored private var downCounts: [ControlAction: Int] = [:]
    /// Sticky controls that are down, with what they hold.
    @ObservationIgnored private var stickies: [UUID: ControlAction] = [:]
    /// Advances when everything is let go, so touches from before change nothing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

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
    }

    public func state(of id: UUID) -> ControlState {
        if let state = states[id] { return state }
        let state = ControlState()
        states[id] = state
        return state
    }

    /// Lets go of everything the controls hold down.
    public func releaseAll() {
        for action in downCounts.keys { send(action, down: false) }
        downCounts = [:]
        stickies = [:]
        generation += 1
        for state in states.values {
            state.pressed = false
            state.latched = false
            state.pressedKey = nil
        }
    }

    func setArea(bounds: CGRect, safeArea: CGRect) {
        if self.bounds != bounds { self.bounds = bounds }
        if self.safeArea != safeArea { self.safeArea = safeArea }
    }

    /// A click on the game has been let go: sticky keys go up after it.
    func mouseButtonReleased() {
        releaseStickies()
    }

    // MARK: Touches

    struct Touch {
        let control: UUID
        let action: ControlAction
        let behaviour: PressBehaviour
        let generation: Int
        let began: CFTimeInterval
    }

    /// The control at `point` that takes touches, with the key for a key row.
    func control(at point: CGPoint) -> (control: Control, key: Int?)? {
        guard let layout else { return nil }
        for control in layout.controls.reversed() {
            let frame = control.placement.frame(in: safeArea)
            guard frame.contains(point) else { continue }
            switch control.kind {
            case .button(let button) where Self.works(button.action):
                return (control, nil)
            case .keyRow(let row):
                if let key = row.keyIndex(at: point.x, in: frame) { return (control, key) }
            default:
                continue
            }
        }
        return nil
    }

    /// What this version sends to the game.
    private static func works(_ action: ControlAction) -> Bool {
        switch action {
        case .key, .mouse, .wheel: true
        case .pad, .keyboard: false
        }
    }

    func began(_ control: Control, key: Int?) -> Touch? {
        let state = state(of: control.id)
        let action: ControlAction, behaviour: PressBehaviour
        switch control.kind {
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
        return Touch(control: control.id, action: action, behaviour: behaviour,
                     generation: generation, began: CACurrentMediaTime())
    }

    func ended(_ touch: Touch) {
        let state = state(of: touch.control)
        state.pressed = false
        state.pressedKey = nil
        guard touch.behaviour == .press, touch.generation == generation else { return }
        let wait = Self.shortestPress - (CACurrentMediaTime() - touch.began)
        guard wait > 0 else { return finishPress(touch) }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated { self?.finishPress(touch) }
        }
    }

    private func finishPress(_ touch: Touch) {
        guard touch.generation == generation else { return }
        release(touch.action)
        releaseStickies()
    }

    // MARK: Sending

    private func releaseStickies() {
        guard !stickies.isEmpty else { return }
        for (id, action) in stickies {
            release(action)
            states[id]?.latched = false
        }
        stickies = [:]
    }

    private func press(_ action: ControlAction) {
        let count = downCounts[action, default: 0]
        downCounts[action] = count + 1
        if count == 0 { send(action, down: true) }
    }

    private func release(_ action: ControlAction) {
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
        case .pad, .keyboard:
            break
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

    /// Whether a touch at `point` (in this view) is on a control.
    public func owns(_ point: CGPoint) -> Bool {
        runtime.control(at: point) != nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        runtime.setArea(bounds: bounds, safeArea: bounds.inset(by: safeAreaInsets))
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let hit = runtime.control(at: touch.location(in: self)),
                  let record = runtime.began(hit.control, key: hit.key) else { continue }
            touchesOnControls[ObjectIdentifier(touch)] = record
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let record = touchesOnControls.removeValue(forKey: ObjectIdentifier(touch)) { runtime.ended(record) }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
