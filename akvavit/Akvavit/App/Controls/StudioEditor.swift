// SPDX-License-Identifier: GPL-3.0-or-later
//
// A layout of yours in the studio, editable (the canvas's studio boards): a
// tap selects a control, a drag moves it, the selected one's corners resize
// it. While a finger is down, dashed lines show what its edges line up with,
// and a resize shows the size. Drawn with the same faces as in play.

import AkvavitKit
import SwiftUI

struct StudioEditor: View {
    /// Drags are measured here: a control's own place moves with the drag.
    private static let space = "studio"

    let layout: ControlLayout
    /// The whole display, in this view's coordinates.
    let area: CGRect
    let model: StudioModel
    let save: (ControlLayout) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A tap on the empty screen lets go of the selection.
            Color.clear
                .contentShape(.rect)
                .onTapGesture { model.selected = nil }
            // Trackpads under everything else, as in play.
            ForEach(layout.controls.filter(\.isTrackpad) + layout.controls.filter { !$0.isTrackpad }) { control in
                let frame = model.frame(of: control, in: area)
                ControlFace(control: control, state: nil, opacity: control.opacity)
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(.rect)
                    .gesture(move(control))
                    .position(x: frame.midX, y: frame.midY)
            }
            guides
            if let id = model.selected, let control = layout.controls.first(where: { $0.id == id }) {
                selection(control, frame: model.frame(of: control, in: area))
            }
        }
        .frame(width: area.width, height: area.height)
        .coordinateSpace(.named(Self.space))
    }

    private func move(_ control: Control) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if model.live?.id != control.id { model.beginMove(control, in: area) }
                model.move(by: drag.translation, in: layout, area: area)
            }
            .onEnded { drag in
                // A tap only selects.
                guard hypot(drag.translation.width, drag.translation.height) > 4 else { return model.cancel() }
                if let changed = model.finish(layout, area: area) { save(changed) } else { model.cancel() }
            }
    }

    private func resize(_ control: Control, _ corner: StudioModel.Corner) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if model.live?.id != control.id { model.beginResize(control, in: area) }
                model.resize(control, corner: corner, by: drag.translation, area: area)
            }
            .onEnded { _ in
                if let changed = model.finish(layout, area: area) { save(changed) } else { model.cancel() }
            }
    }

    // MARK: Marks

    private var guides: some View {
        Path { path in
            for x in model.guides.x {
                path.move(to: CGPoint(x: x, y: area.minY))
                path.addLine(to: CGPoint(x: x, y: area.maxY))
            }
            for y in model.guides.y {
                path.move(to: CGPoint(x: area.minX, y: y))
                path.addLine(to: CGPoint(x: area.maxX, y: y))
            }
            for line in model.diagonals {
                path.move(to: CGPoint(x: area.minX, y: line.slope * area.minX + line.offset))
                path.addLine(to: CGPoint(x: area.maxX, y: line.slope * area.maxX + line.offset))
            }
        }
        .stroke(StudioMarks.glow, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        .allowsHitTesting(false)
    }

    /// The ring around the selected control, its corner handles, and its size
    /// while it is being resized.
    private func selection(_ control: Control, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: StudioMarks.cornerRadius(of: control, frame: frame) + 6, style: .continuous)
                .stroke(StudioMarks.glow, lineWidth: 2)
                .frame(width: frame.width + 12, height: frame.height + 12)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)
            ForEach(StudioModel.Corner.allCases, id: \.self) { corner in
                let point = StudioMarks.point(of: corner, in: frame.insetBy(dx: -10, dy: -10))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .strokeBorder(Theme.controlsColors.tint, lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .frame(width: 44, height: 44)   // a finger-sized target
                    .contentShape(.rect)
                    .gesture(resize(control, corner))
                    .position(point)
                    .accessibilityLabel("Resize")
            }
            if model.resizing {
                Text("\(Int(frame.width.rounded())) × \(Int(frame.height.rounded())) pt")
                    .font(.quicksand(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.controlsColors.tint, in: .capsule)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
                    .fixedSize()
                    .position(StudioMarks.readout(for: frame, in: area))
                    .allowsHitTesting(false)
            }
        }
    }
}

private enum StudioMarks {
    static let glow = Color(hex: 0xC9B3FF)

    static func point(of corner: StudioModel.Corner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .topRight: CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    /// Up and to the right of the control, or wherever it fits on the display.
    static func readout(for frame: CGRect, in area: CGRect) -> CGPoint {
        let x = frame.maxX + 70 < area.maxX ? frame.maxX + 64 : frame.minX - 64
        let y = frame.minY - 30 > area.minY ? frame.minY - 24 : frame.maxY + 24
        return CGPoint(x: min(max(x, area.minX + 64), area.maxX - 64), y: y)
    }

    /// The face's own corner, so the ring follows its shape.
    static func cornerRadius(of control: Control, frame: CGRect) -> CGFloat {
        let side = min(frame.width, frame.height)
        switch control.kind {
        case .button(let button): return button.shape == .round ? side / 2 : side * 0.225
        case .stick: return side / 2
        case .trackpad: return 22
        case .keyRow: return 9
        }
    }
}

extension Control {
    var isTrackpad: Bool {
        if case .trackpad = kind { true } else { false }
    }
}
