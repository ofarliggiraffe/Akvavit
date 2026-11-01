// SPDX-License-Identifier: GPL-3.0-or-later
//
// How on-screen controls look (the design canvas's "Controls" boards). One
// renderer for the controls over a game, the studio and the Controls tab, so
// a layout looks the same everywhere.

import AkvavitKit
import SwiftUI

/// A layout's controls at their places. The canvas fills its parent; `area`
/// (the display) is in the parent's coordinates.
struct ControlsCanvas: View {
    let layout: ControlLayout
    let area: CGRect
    /// Over a game: trackpads are invisible there (only the studio shows them).
    var inPlay = false
    /// The live state of each control (in play); nil draws it at rest.
    var state: (UUID) -> ControlState? = { _ in nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Trackpads under everything else: buttons over them take the touch.
            ForEach(layout.controls.filter(\.isTrackpad) + layout.controls.filter { !$0.isTrackpad }) { control in
                if !(inPlay && control.isTrackpad) {
                    let frame = control.placement.frame(in: area)
                    ControlFace(control: control, state: state(control.id), opacity: control.opacity)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension Control {
    var isTrackpad: Bool {
        if case .trackpad = kind { true } else { false }
    }
}

struct ControlFace: View {
    let control: Control
    let state: ControlState?
    /// The control's opacity. Labels are twice as solid as the rest, so a
    /// see-through button stays readable.
    let opacity: Double

    var body: some View {
        let label = min(1, opacity * 2)
        switch control.kind {
        case .button(let button): ButtonFace(button: button, state: state, fill: opacity, label: label)
        case .keyRow(let row): KeyRowFace(row: row, state: state, fill: opacity, label: label)
        case .trackpad(let pad): TrackpadFace(pad: pad, state: state).opacity(opacity)
        case .stick(let stick): StickFace(stick: stick, state: state).opacity(opacity)
        }
    }
}

/// Colours of the controls, drawn over any game (so the same in dark mode).
private enum ControlColors {
    static let ink = Color(hex: 0x20243A)
    static let glow = Color(hex: 0xC9B3FF)
    static let lilac = Color(hex: 0x7A4FD6)

    static func fill(_ colour: ControlButton.Colour, down: Bool) -> Color {
        switch colour {
        case .plain: Color.white.opacity(down ? 1 : 0.85)
        case .lilac: Color(hex: down ? 0x8F63F0 : 0x7A4FD6)
        case .red: Color(hex: down ? 0xF0645C : 0xE0524A)
        case .yellow: Color(hex: down ? 0xF7CF6E : 0xF2C14E)
        case .blue: Color(hex: down ? 0x63A2EB : 0x4A90E2)
        case .green: Color(hex: down ? 0x72C872 : 0x5CB85C)
        }
    }

    static func text(_ colour: ControlButton.Colour) -> Color {
        colour == .plain || colour == .yellow ? ink : .white
    }

    static func font(_ size: CGFloat) -> Font {
        .custom(QuicksandWeight.bold.fontName, fixedSize: size)
    }
}

struct ButtonFace: View {
    let button: ControlButton
    let state: ControlState?
    let fill: Double
    let label: Double

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let pressed = state?.pressed == true
            let latched = state?.latched == true
            let shape = RoundedRectangle(cornerRadius: button.shape == .round ? side / 2 : side * 0.225,
                                         style: .continuous)
            ZStack {
                if latched {
                    shape.inset(by: -6).stroke(ControlColors.glow, lineWidth: 3).opacity(label)
                }
                shape.fill(ControlColors.fill(button.colour, down: pressed || latched)).opacity(fill)
                Text(button.title)
                    .font(ControlColors.font(min(17, side * 0.2)))
                    .foregroundStyle(ControlColors.text(button.colour))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(side * 0.1)
                    .opacity(label)
                if button.whenTapped == .sticky {
                    Image(systemName: "pin.fill")
                        .font(.system(size: max(side * 0.15, 9)))
                        .foregroundStyle(ControlColors.text(button.colour))
                        .opacity((latched ? 1 : 0.35) * label)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(side * 0.09)
                }
            }
            .scaleEffect(pressed ? 0.92 : 1)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct KeyRowFace: View {
    let row: ControlKeyRow
    let state: ControlState?
    let fill: Double
    let label: Double

    var body: some View {
        GeometryReader { geometry in
            let frames = row.keyFrames(in: CGRect(origin: .zero, size: geometry.size))
            ForEach(row.keys.indices, id: \.self) { index in
                let frame = frames[index]
                let pressed = state?.pressedKey == index
                RoundedRectangle(cornerRadius: min(9, frame.height * 0.28), style: .continuous)
                    .fill(Color.white.opacity(pressed ? 1 : 0.82))
                    .opacity(fill)
                    .overlay {
                        Text(VirtualKey.name(row.keys[index]))
                            .font(ControlColors.font(min(14, frame.height * 0.45)))
                            .foregroundStyle(ControlColors.ink)
                            .minimumScaleFactor(0.5)
                            .opacity(label)
                    }
                    .scaleEffect(pressed ? 0.9 : 1)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}

struct TrackpadFace: View {
    let pad: ControlTrackpad
    let state: ControlState?

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(state?.pressed == true ? 0.14 : 0.06))
            .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .overlay {
                Text(title)
                    .font(ControlColors.font(16))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
    }

    private var title: String {
        switch pad.mode {
        case .mouse: "Trackpad"
        case .aim: "Aim"
        case .move: "Move · WASD"
        }
    }
}

struct StickFace: View {
    let stick: ControlStick
    let state: ControlState?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let knob = state?.knob ?? .zero
            let reach = side * ControlsRuntime.stickReach
            ZStack {
                Circle()
                    .fill(ControlColors.lilac.opacity(state?.pressed == true ? 0.3 : 0.15))
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 3)
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: side * 0.4, height: side * 0.4)
                    .offset(x: knob.x * reach, y: knob.y * reach)
                if stick.worksAs == .wasd {
                    letters(side, knob: knob)
                }
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    /// W A S D, lit in the direction pushed.
    private func letters(_ side: CGFloat, knob: CGPoint) -> some View {
        let font = ControlColors.font(min(14, side * 0.08))
        let inset = side * 0.06
        let dead = CGFloat(stick.deadZone)
        func lit(_ on: Bool) -> Color { on ? ControlColors.glow : .white }
        return ZStack {
            Text("W").foregroundStyle(lit(knob.y < -dead)).frame(maxHeight: .infinity, alignment: .top).padding(.top, inset)
            Text("S").foregroundStyle(lit(knob.y > dead)).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, inset)
            Text("A").foregroundStyle(lit(knob.x < -dead)).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, inset)
            Text("D").foregroundStyle(lit(knob.x > dead)).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, inset)
        }
        .font(font)
    }
}
