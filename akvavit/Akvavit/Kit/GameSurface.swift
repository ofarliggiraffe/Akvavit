// SPDX-License-Identifier: GPL-3.0-or-later
//
// GameSurfaceView: where a session's picture is shown, and where touches
// become the Windows mouse.
//
// The picture itself is drawn into one CAMetalLayer for the whole app run
// (GameLayerHost), which sits directly on the window, above the interface,
// and lets touches through. The engine needs that: a Metal layer inside a
// SwiftUI-hosted view loses presented frames, and DXMT keeps drawing into the
// first layer it was given. GameSurfaceView is an ordinary view in the
// interface; it places the host over its own area and takes the touches.
//
// Geometry comes from the view and its window, never from UIScreen.main
// (on the iPhone Duo that is always the outer display).

import Metal
import QuartzCore
import UIKit

/// The window-level view whose CAMetalLayer the engine draws into.
final class GameLayerHost: UIView {
    static let shared = GameLayerHost(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    private static var registered = false

    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        // Present frames as they come, outside the display's sync scheduling.
        // Madeira found presents dropped without it (iOS: private, so by name).
        let syncOff = NSSelectorFromString("setDisplaySyncEnabled:")
        if metalLayer.responds(to: syncOff) { metalLayer.perform(syncOff, with: NSNumber(value: false)) }
        // A non-zero size before DXMT sets its own, so its setup never waits.
        metalLayer.drawableSize = CGSize(width: 800, height: 600)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Puts the host on `window` (once per window) and hands the layer to the
    /// engine (once per app run).
    func attach(to window: UIWindow) {
        if superview !== window {
            removeFromSuperview()
            window.addSubview(self)
        }
        window.bringSubviewToFront(self)
        contentScaleFactor = window.screen.scale
        if !Self.registered {
            Self.registered = true
            madeira_display_set_layer(metalLayer)
        }
    }
}

/// Mouse event flags of Windows' SendInput (MOUSEEVENTF_*).
private enum MouseFlags {
    static let move: UInt32 = 0x0001
    static let leftDown: UInt32 = 0x0002
    static let leftUp: UInt32 = 0x0004
    static let rightDown: UInt32 = 0x0008
    static let rightUp: UInt32 = 0x0010
    static let middleDown: UInt32 = 0x0020
    static let middleUp: UInt32 = 0x0040
    static let wheel: UInt32 = 0x0800
    static let absolute: UInt32 = 0x8000
}

public final class GameSurfaceView: UIView {
    /// A tap with four fingers: not passed to the game, but to this.
    public var onFourFingerTap: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var drawableWatch: NSKeyValueObservation?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        observers.append(NotificationCenter.default.addObserver(
            forName: .MadeiraDisplayModeChanged, object: nil, queue: .main) { [weak self] _ in
                self?.setNeedsLayout()
            })
        drawableWatch = GameLayerHost.shared.metalLayer.observe(\.drawableSize) { [weak self] _, _ in
            DispatchQueue.main.async { self?.setNeedsLayout() }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Layout

    /// The Windows screen's size in pixels (a game can change it).
    private var guestSize: CGSize {
        var w: Int32 = 0, h: Int32 = 0
        winios_screen_size(&w, &h)
        return w > 0 && h > 0 ? CGSize(width: Int(w), height: Int(h)) : CGSize(width: 1024, height: 768)
    }

    /// Where the picture goes in this view: the Windows screen, as large as fits.
    private var pictureRect: CGRect {
        let guest = guestSize
        let scale = min(bounds.width / guest.width, bounds.height / guest.height)
        guard scale.isFinite, scale > 0 else { return bounds }
        let size = CGSize(width: (guest.width * scale).rounded(), height: (guest.height * scale).rounded())
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        GameLayerHost.shared.attach(to: window)
        // Gesture recognizers of the views around this one (SwiftUI's
        // presentation adds some) may claim a multi-finger touch and cancel it
        // here. Ours to handle: they keep seeing touches but no longer cancel them.
        var view: UIView? = self
        while let current = view {
            for recognizer in current.gestureRecognizers ?? [] {
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
            }
            view = current.superview
        }
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        let picture = pictureRect
        GameLayerHost.shared.frame = convert(picture, to: window)
        // Windows' desktop (drawn by the engine's own compositor) uses the same area.
        let full = convert(bounds, to: window)
        winios_set_compositor_frame(full.minX, full.minY, full.width, full.height)
        winios_set_desktop_rect(picture.minX, picture.minY, picture.width, picture.height, 1)
    }

    // MARK: Touch as mouse
    //
    // One finger: a tap clicks; a drag (past 10 pt, or after holding 0.25 s)
    // holds the left button from where it started, so boxes can be drawn.
    // Two fingers tapped: right click; three: middle click. Two fingers moved
    // up or down: the wheel.

    private enum Gesture {
        case none
        case pending(start: CGPoint)
        case dragging
        case fingers(count: Int, start: CGPoint, scrolled: CGFloat)
    }

    private var gesture = Gesture.none
    private var holdTimer: Timer?
    private var lastPoint = CGPoint.zero
    private static let dragDistance: CGFloat = 10
    private static let holdTime: TimeInterval = 0.25
    private static let pointsPerWheelNotch: CGFloat = 20

    /// A point in this view, in Windows screen pixels.
    private func windowsPoint(_ point: CGPoint) -> (Int32, Int32) {
        if Session.shared.config?.isDesktop == true, let window {
            let p = convert(point, to: window)
            var x: Int32 = 0, y: Int32 = 0
            if winios_desktop_point_from_window(p.x, p.y, &x, &y) != 0 { return (x, y) }
        }
        let picture = pictureRect
        var target = CGRect(origin: .zero, size: guestSize)
        var cx: Int32 = 0, cy: Int32 = 0, cw: Int32 = 0, ch: Int32 = 0
        if winios_game_client_rect(&cx, &cy, &cw, &ch) != 0, cw > 0, ch > 0 {
            target = CGRect(x: Int(cx), y: Int(cy), width: Int(cw), height: Int(ch))
        }
        let u = min(max((point.x - picture.minX) / max(picture.width, 1), 0), 1)
        let v = min(max((point.y - picture.minY) / max(picture.height, 1), 0), 1)
        let x = target.minX + u * (target.width - 1)
        let y = target.minY + v * (target.height - 1)
        return (Int32(x.rounded()), Int32(y.rounded()))
    }

    private func send(_ point: CGPoint, _ flags: UInt32, data: UInt32 = 0) {
        // A control layout can leave the game without touch (shooters); four
        // fingers still open the menu.
        let controls = ControlsRuntime.shared
        guard controls.touchAsMouse else { return }
        let (x, y) = windowsPoint(point)
        winios_pointer(x, y, flags | MouseFlags.absolute | MouseFlags.move, data)
        controls.pointerMoved(toX: x, y: y)
        if flags & (MouseFlags.leftUp | MouseFlags.rightUp | MouseFlags.middleUp) != 0 {
            controls.mouseButtonReleased()
        }
    }

    /// One line per gesture in the session log (stderr goes to madeira-log.txt).
    private func note(_ what: String, at point: CGPoint) {
        let (x, y) = windowsPoint(point)
        fputs("[touch] \(what) at \(x),\(y)\n", stderr)
    }

    private func midpoint(_ touches: Set<UITouch>) -> CGPoint {
        let points = touches.map { $0.location(in: self) }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(max(points.count, 1)), y: sum.y / CGFloat(max(points.count, 1)))
    }

    private func activeTouches(_ event: UIEvent?) -> Set<UITouch> {
        (event?.touches(for: self) ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
    }

    private func beginDrag(from start: CGPoint) {
        holdTimer?.invalidate()
        gesture = .dragging
        note("drag", at: start)
        send(start, MouseFlags.leftDown)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = activeTouches(event)
        switch gesture {
        case .none where active.count == 1:
            let start = touches.first!.location(in: self)
            lastPoint = start
            gesture = .pending(start: start)
            send(start, 0)   // the pointer goes there first, as a hovering mouse would
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdTime, repeats: false) { [weak self] _ in
                guard let self, case .pending(let start) = self.gesture else { return }
                self.beginDrag(from: start)
            }
        case .none, .pending:
            holdTimer?.invalidate()
            gesture = .fingers(count: active.count, start: midpoint(active), scrolled: 0)
        case .fingers(let count, let start, let scrolled):
            gesture = .fingers(count: max(count, active.count), start: start, scrolled: scrolled)
        case .dragging:
            break
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch gesture {
        case .pending(let start):
            guard let point = touches.first?.location(in: self) else { return }
            lastPoint = point
            if hypot(point.x - start.x, point.y - start.y) > Self.dragDistance {
                beginDrag(from: start)
                send(point, 0)
            }
        case .dragging:
            guard let point = touches.first?.location(in: self) else { return }
            lastPoint = point
            send(point, 0)
        case .fingers(let count, let start, let scrolled):
            guard count == 2 else { return }
            let now = midpoint(activeTouches(event))
            let moved = now.y - start.y
            // Each 20 pt is one wheel notch (120). Natural scrolling, as on iOS:
            // fingers moving up move the content up (the wheel turns down).
            let notches = Int((moved - scrolled) / Self.pointsPerWheelNotch)
            guard notches != 0 else { return }
            note("wheel \(notches)", at: start)
            send(start, MouseFlags.wheel, data: UInt32(bitPattern: Int32(notches * 120)))
            gesture = .fingers(count: count, start: start,
                               scrolled: scrolled + CGFloat(notches) * Self.pointsPerWheelNotch)
        case .none:
            break
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouches(event).isEmpty else { return }
        holdTimer?.invalidate()
        switch gesture {
        case .pending(let start):
            note("tap", at: start)
            send(start, MouseFlags.leftDown)
            send(start, MouseFlags.leftUp)
        case .dragging:
            send(lastPoint, MouseFlags.leftUp)
        case .fingers(let count, let start, let scrolled) where scrolled == 0:
            note("\(count) fingers", at: start)
            if count == 2 {
                send(start, MouseFlags.rightDown)
                send(start, MouseFlags.rightUp)
            } else if count == 3 {
                send(start, MouseFlags.middleDown)
                send(start, MouseFlags.middleUp)
            } else if count == 4 {
                onFourFingerTap?()
            }
        case .fingers, .none:
            break
        }
        gesture = .none
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTimer?.invalidate()
        note("cancelled", at: lastPoint)
        if case .dragging = gesture { send(lastPoint, MouseFlags.leftUp) }
        gesture = .none
    }
}
