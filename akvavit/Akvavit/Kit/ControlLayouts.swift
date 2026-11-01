// SPDX-License-Identifier: GPL-3.0-or-later
//
// On-screen control layouts: what a layout holds, where each control sits,
// and what it sends to the game. Kept as JSON (ControlLayoutStore); every
// part decodes leniently, so a field or control kind this version doesn't
// know never loses a layout.
//
// Places are in points, measured from the edge (or centre) of the display
// that the control is nearest to, so a layout keeps its shape on every iPhone
// and iPad and across the Duo's two displays. The whole display counts: a game
// fills it, safe area included (the user's call).

import CoreGraphics
import Foundation

public struct ControlLayout: Identifiable, Codable, Equatable, Sendable {
    /// What a finger on the game itself (not on a control) does.
    public enum GameTouch: String, Codable, Sendable {
        case mouse
        case off
    }

    /// "builtin.…" for built-in layouts, a UUID for the user's.
    public var id: String
    public var name: String
    /// The name of the layout this one was copied from.
    public var copiedFrom: String?
    public var controls: [Control]
    public var gameTouch = GameTouch.mouse
    /// Off: no haptics for any control of this layout.
    public var haptics = true

    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    public init(id: String, name: String, copiedFrom: String? = nil, controls: [Control],
                gameTouch: GameTouch = .mouse, haptics: Bool = true) {
        self.id = id
        self.name = name
        self.copiedFrom = copiedFrom
        self.controls = controls
        self.gameTouch = gameTouch
        self.haptics = haptics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.value(.name, or: "Layout")
        copiedFrom = c.value(.copiedFrom, or: nil)
        controls = c.value(.controls, or: [Lenient<Control>]()).compactMap(\.value)
        gameTouch = c.value(.gameTouch, or: .mouse)
        haptics = c.value(.haptics, or: true)
    }
}

public struct Control: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case button(ControlButton)
        /// A row of keys, moved and sized as one control (the number row).
        case keyRow(ControlKeyRow)
        case trackpad(ControlTrackpad)
        case stick(ControlStick)
    }

    public var id = UUID()
    public var placement: Placement
    public var haptics = true
    /// How solid it looks over the game, 0 to 1.
    public var opacity = Control.defaultOpacity
    public var kind: Kind

    public static let defaultOpacity = 0.35

    public init(_ kind: Kind, _ placement: Placement) {
        self.kind = kind
        self.placement = placement
    }
}

// MARK: Places

public struct Placement: Codable, Equatable, Sendable {
    /// Which edge of the display a control is measured from, per axis:
    /// left or top (`start`), the middle, right or bottom (`end`).
    public enum Anchor: String, Codable, Sendable {
        case start, center, end
    }

    public var horizontal: Anchor
    public var vertical: Anchor
    /// From the anchor: the gap between that edge and the control's own edge,
    /// or, for `center`, how far the control's centre is from the middle.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ horizontal: Anchor, _ x: Double, _ vertical: Anchor, _ y: Double,
                width: Double, height: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The control's frame in `area` (the display). It never leaves the
    /// area: a control larger than the area shrinks to it.
    public func frame(in area: CGRect) -> CGRect {
        let w = min(width, area.width), h = min(height, area.height)
        return CGRect(x: Self.origin(horizontal, x, w, area.minX, area.maxX),
                      y: Self.origin(vertical, y, h, area.minY, area.maxY),
                      width: w, height: h)
    }

    private static func origin(_ anchor: Anchor, _ offset: Double, _ size: CGFloat,
                               _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        let origin: CGFloat = switch anchor {
        case .start: low + offset
        case .end: high - offset - size
        case .center: (low + high) / 2 + offset - size / 2
        }
        return min(max(origin, low), high - size)
    }

    /// The placement of `frame` in `area`, measured from the nearest edge or
    /// the middle, whichever is closest.
    public static func anchored(_ frame: CGRect, in area: CGRect) -> Placement {
        func axis(_ low: CGFloat, _ high: CGFloat, _ min: CGFloat, _ max: CGFloat) -> (Anchor, Double) {
            let toStart = min - low, toEnd = high - max, fromMiddle = (min + max) / 2 - (low + high) / 2
            if abs(fromMiddle) < Swift.min(toStart, toEnd) { return (.center, fromMiddle) }
            return toStart <= toEnd ? (.start, toStart) : (.end, toEnd)
        }
        let (h, x) = axis(area.minX, area.maxX, frame.minX, frame.maxX)
        let (v, y) = axis(area.minY, area.maxY, frame.minY, frame.maxY)
        return Placement(h, x, v, y, width: frame.width, height: frame.height)
    }

    /// The same place on the other side (left and right swapped).
    public func mirrored() -> Placement {
        var copy = self
        switch horizontal {
        case .start: copy.horizontal = .end
        case .end: copy.horizontal = .start
        case .center: copy.x = -x
        }
        return copy
    }
}

// MARK: What controls send

/// What a button sends. Stored as short text ("key:17", "mouse:left").
public enum ControlAction: Hashable, Codable, Sendable {
    /// A Windows virtual key (VK_*).
    case key(Int)
    case mouse(MouseButton)
    case wheel(Wheel)
    case pad(PadButton)
    /// Brings up the iPhone's keyboard, for typing into the game.
    case keyboard

    public enum MouseButton: String, Codable, Sendable { case left, right, middle }
    public enum Wheel: String, Codable, Sendable { case up, down }

    /// Controller buttons (XInput's).
    public enum PadButton: String, Codable, CaseIterable, Sendable {
        case a, b, x, y, lb, rb, lt, rt, start, back, leftStick, rightStick, up, down, left, right
    }

    public init?(text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : nil) {
        case ("key", let value?): guard let vk = Int(value) else { return nil }; self = .key(vk)
        case ("mouse", let value?): guard let b = MouseButton(rawValue: value) else { return nil }; self = .mouse(b)
        case ("wheel", let value?): guard let w = Wheel(rawValue: value) else { return nil }; self = .wheel(w)
        case ("pad", let value?): guard let b = PadButton(rawValue: value) else { return nil }; self = .pad(b)
        case ("keyboard", nil): self = .keyboard
        default: return nil
        }
    }

    public var text: String {
        switch self {
        case .key(let vk): "key:\(vk)"
        case .mouse(let button): "mouse:\(button.rawValue)"
        case .wheel(let wheel): "wheel:\(wheel.rawValue)"
        case .pad(let button): "pad:\(button.rawValue)"
        case .keyboard: "keyboard"
        }
    }

    /// The name shown on a button without a label of its own.
    public var name: String {
        switch self {
        case .key(let vk): VirtualKey.name(vk)
        case .mouse(.left): "Left click"
        case .mouse(.right): "Right click"
        case .mouse(.middle): "Middle click"
        case .wheel(.up): "Wheel up"
        case .wheel(.down): "Wheel down"
        case .pad(let button): button.name
        case .keyboard: "Keyboard"
        }
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let action = ControlAction(text: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown action \(text)"))
        }
        self = action
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

extension ControlAction.PadButton {
    public var name: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .lb: "LB"
        case .rb: "RB"
        case .lt: "LT"
        case .rt: "RT"
        case .start: "Start"
        case .back: "Back"
        case .leftStick: "Left stick"
        case .rightStick: "Right stick"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// What tapping a button does with what it sends.
public enum PressBehaviour: String, Codable, CaseIterable, Sendable {
    /// Down while the finger is on it.
    case press
    /// One tap puts it down, the next lets it go.
    case hold
    /// Down until the next key or click has been let go; a second tap lets it go.
    case sticky
}

// MARK: Kinds of controls

public struct ControlButton: Codable, Equatable, Sendable {
    public enum Shape: String, Codable, Sendable { case round, rounded }
    public enum Colour: String, Codable, Sendable { case plain, lilac, red, yellow, blue, green }

    public var action: ControlAction
    /// Shown instead of the action's name.
    public var label: String?
    public var whenTapped = PressBehaviour.press
    public var shape = Shape.round
    public var colour = Colour.plain

    public init(_ action: ControlAction, label: String? = nil, whenTapped: PressBehaviour = .press,
                shape: Shape = .round, colour: Colour = .plain) {
        self.action = action
        self.label = label
        self.whenTapped = whenTapped
        self.shape = shape
        self.colour = colour
    }

    public var title: String { label ?? action.name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(ControlAction.self, forKey: .action)
        label = c.value(.label, or: nil)
        whenTapped = c.value(.whenTapped, or: .press)
        shape = c.value(.shape, or: .round)
        colour = c.value(.colour, or: .plain)
    }
}

public struct ControlKeyRow: Codable, Equatable, Sendable {
    /// Windows virtual keys, left to right.
    public var keys: [Int]

    /// 1 to 0, as on a keyboard.
    public static let numbers = ControlKeyRow(keys: Array(0x31...0x39) + [0x30])

    public init(keys: [Int]) { self.keys = keys }

    /// The gap between keys, in points.
    public static let gap: CGFloat = 8

    /// Each key's frame when the row fills `frame`.
    public func keyFrames(in frame: CGRect) -> [CGRect] {
        guard !keys.isEmpty else { return [] }
        let n = CGFloat(keys.count)
        let width = max((frame.width - Self.gap * (n - 1)) / n, 1)
        return keys.indices.map { i in
            CGRect(x: frame.minX + CGFloat(i) * (width + Self.gap), y: frame.minY, width: width, height: frame.height)
        }
    }

    /// The key nearest to `x` (gaps count for the nearer key).
    public func keyIndex(at x: CGFloat, in frame: CGRect) -> Int? {
        guard !keys.isEmpty else { return nil }
        let pitch = frame.width / CGFloat(keys.count)
        return min(max(Int((x - frame.minX) / pitch), 0), keys.count - 1)
    }
}

public struct ControlTrackpad: Codable, Equatable, Sendable {
    /// A trackpad only moves; clicks are buttons.
    public enum Mode: String, Codable, Sendable {
        /// Moves the Windows cursor.
        case mouse
        /// Turns the view, for games that hide the cursor (relative motion).
        case aim
        /// W, A, S and D, held in the direction the finger moves.
        case move
    }

    public var mode: Mode
    public var speed = 1.0

    public init(_ mode: Mode) { self.mode = mode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(Mode.self, forKey: .mode)
        speed = c.value(.speed, or: 1.0)
    }
}

public struct ControlStick: Codable, Equatable, Sendable {
    public enum WorksAs: String, Codable, Sendable {
        case leftStick, rightStick, wasd, arrows, mouse
    }

    public var worksAs: WorksAs
    /// Part of the stick's reach that does nothing, 0 to 1.
    public var deadZone = 0.2
    public var centreWhereThumbLands = true

    public init(_ worksAs: WorksAs) { self.worksAs = worksAs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        worksAs = try c.decode(WorksAs.self, forKey: .worksAs)
        deadZone = c.value(.deadZone, or: 0.2)
        centreWhereThumbLands = c.value(.centreWhereThumbLands, or: true)
    }
}

// MARK: Storing

extension Control: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, placement, haptics, opacity, type, button, keyRow, trackpad, stick
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        placement = try c.decode(Placement.self, forKey: .placement)
        haptics = c.value(.haptics, or: true)
        opacity = c.value(.opacity, or: Control.defaultOpacity)
        switch try c.decode(String.self, forKey: .type) {
        case "button": kind = .button(try c.decode(ControlButton.self, forKey: .button))
        case "keyRow": kind = .keyRow(try c.decode(ControlKeyRow.self, forKey: .keyRow))
        case "trackpad": kind = .trackpad(try c.decode(ControlTrackpad.self, forKey: .trackpad))
        case "stick": kind = .stick(try c.decode(ControlStick.self, forKey: .stick))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown control \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(placement, forKey: .placement)
        try c.encode(haptics, forKey: .haptics)
        try c.encode(opacity, forKey: .opacity)
        switch kind {
        case .button(let button): try c.encode("button", forKey: .type); try c.encode(button, forKey: .button)
        case .keyRow(let row): try c.encode("keyRow", forKey: .type); try c.encode(row, forKey: .keyRow)
        case .trackpad(let pad): try c.encode("trackpad", forKey: .type); try c.encode(pad, forKey: .trackpad)
        case .stick(let stick): try c.encode("stick", forKey: .type); try c.encode(stick, forKey: .stick)
        }
    }
}

/// An element that is skipped, instead of failing the whole list, when it
/// can't be read.
struct Lenient<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when it is missing or unreadable.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
