// SPDX-License-Identifier: GPL-3.0-or-later
//
// Editing in the controls studio: the selected control, moving and resizing
// it, the grid it snaps to, and the lines that show what its edges line up
// with. (No previews of other displays: people make a layout on the device
// they play on, the user's call.) A control's new place is kept measured from the display's nearest
// edge (or its middle), so it stays there on other displays.
//
// The grid is centred on the display, so both sides have the same margins
// and Mirror keeps controls on it. A control snaps by its edge nearest the
// display's edge (its middle when it sits in the middle). With the grid off,
// edges snap to other controls' edges and middles, and to the display's
// middle, when they come within 6 points.

import AkvavitKit
import SwiftUI

@MainActor @Observable
final class StudioModel {
    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var selected: UUID?
    /// The control a finger is moving or resizing, and its frame now.
    private(set) var live: (id: UUID, frame: CGRect)?
    private(set) var resizing = false
    /// Lines the live control's edges or middles are on, across the display.
    private(set) var guides: (x: [CGFloat], y: [CGFloat]) = ([], [])

    var snaps = UserDefaults.standard.object(forKey: "akvavit.studio.snap") as? Bool ?? true {
        didSet { UserDefaults.standard.set(snaps, forKey: "akvavit.studio.snap") }
    }
    /// The grid's spacing in points.
    var spacing = UserDefaults.standard.object(forKey: "akvavit.studio.grid") as? Double ?? 24 {
        didSet { UserDefaults.standard.set(spacing, forKey: "akvavit.studio.grid") }
    }
    static let spacings: [Double] = [8, 16, 24, 32, 40]

    @ObservationIgnored private var start = CGRect.zero
    private static let lineSnap: CGFloat = 6

    /// While a finger is on a control, the bars all but disappear.
    var isInteracting: Bool { live != nil }

    func frame(of control: Control, in area: CGRect) -> CGRect {
        if let live, live.id == control.id { return live.frame }
        return control.placement.frame(in: area)
    }

    // MARK: Moving

    func beginMove(_ control: Control, in area: CGRect) {
        selected = control.id
        start = control.placement.frame(in: area)
        live = (control.id, start)
        resizing = false
    }

    func move(by translation: CGSize, in layout: ControlLayout, area: CGRect) {
        guard let id = live?.id else { return }
        var frame = Self.inside(start.offsetBy(dx: translation.width, dy: translation.height), area)
        let others = layout.controls.filter { $0.id != id }.map { $0.placement.frame(in: area) }
        var lines: (x: [CGFloat], y: [CGFloat]) = ([], [])
        frame.origin.x = snap(frame.minX, frame.width, area.minX, area.maxX,
                              others.flatMap { [$0.minX, $0.midX, $0.maxX] }, &lines.x)
        frame.origin.y = snap(frame.minY, frame.height, area.minY, area.maxY,
                              others.flatMap { [$0.minY, $0.midY, $0.maxY] }, &lines.y)
        live = (id, Self.inside(frame, area))
        guides = lines
    }

    /// One axis: the control's start edge after snapping.
    private func snap(_ origin: CGFloat, _ size: CGFloat, _ low: CGFloat, _ high: CGFloat,
                      _ others: [CGFloat], _ lines: inout [CGFloat]) -> CGFloat {
        let middle = (low + high) / 2
        var origin = origin
        if snaps {
            let centre = origin + size / 2
            if abs(centre - middle) < CGFloat(spacing) / 2 {
                origin = middle - size / 2
            } else if centre < middle {
                origin = onGrid(origin, middle)
            } else {
                origin = onGrid(origin + size, middle) - size
            }
        } else {
            var best: CGFloat?
            for edge in [origin, origin + size / 2, origin + size] {
                for line in others + [middle] where abs(line - edge) <= Self.lineSnap {
                    if best == nil || abs(line - edge) < abs(best!) { best = line - edge }
                }
            }
            origin += best ?? 0
        }
        for edge in [origin, origin + size / 2, origin + size] {
            for line in others + [middle] where abs(line - edge) < 0.5 && !lines.contains(line) {
                lines.append(line)
            }
        }
        return origin
    }

    private func onGrid(_ value: CGFloat, _ middle: CGFloat) -> CGFloat {
        let step = CGFloat(spacing)
        return middle + ((value - middle) / step).rounded() * step
    }

    // MARK: Resizing

    func beginResize(_ control: Control, in area: CGRect) {
        beginMove(control, in: area)
        resizing = true
    }

    /// Drags `corner`; the opposite corner stays. Buttons and sticks keep
    /// their shape; trackpads and key rows take any.
    func resize(_ control: Control, corner: Corner, by translation: CGSize, area: CGRect) {
        guard live?.id == control.id else { return }
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let middle = CGPoint(x: area.midX, y: area.midY)
        var x = (left ? start.minX : start.maxX) + translation.width
        var y = (top ? start.minY : start.maxY) + translation.height
        if snaps {
            x = onGrid(x, middle.x)
            y = onGrid(y, middle.y)
        }
        let minimum = Self.minimumSize(control)
        var width = max(left ? start.maxX - x : x - start.minX, minimum.width)
        var height = max(top ? start.maxY - y : y - start.minY, minimum.height)
        if Self.keepsShape(control) {
            let scale = max(width / start.width, height / start.height)
            width = max(start.width * scale, minimum.width)
            height = max(start.height * scale, minimum.height)
        }
        width = min(width, area.width)
        height = min(height, area.height)
        let frame = CGRect(x: left ? start.maxX - width : start.minX, y: top ? start.maxY - height : start.minY,
                           width: width, height: height)
        live = (control.id, Self.inside(frame, area))
        guides = ([], [])
    }

    private static func keepsShape(_ control: Control) -> Bool {
        switch control.kind {
        case .button, .stick: true
        case .trackpad, .keyRow: false
        }
    }

    private static func minimumSize(_ control: Control) -> CGSize {
        switch control.kind {
        case .button: CGSize(width: 32, height: 32)
        case .stick: CGSize(width: 80, height: 80)
        case .trackpad: CGSize(width: 80, height: 80)
        case .keyRow(let row): CGSize(width: CGFloat(row.keys.count) * 24, height: 24)
        }
    }

    // MARK: Ending

    /// The layout with the live control at its new place; nil when nothing changed.
    func finish(_ layout: ControlLayout, area: CGRect) -> ControlLayout? {
        defer { cancel() }
        guard let live, let index = layout.controls.firstIndex(where: { $0.id == live.id }),
              live.frame != layout.controls[index].placement.frame(in: area) else { return nil }
        var changed = layout
        changed.controls[index].placement = Placement.anchored(live.frame, in: area)
        return changed
    }

    func cancel() {
        live = nil
        resizing = false
        guides = ([], [])
    }

    /// Every control on the other side.
    static func mirrored(_ layout: ControlLayout) -> ControlLayout {
        var changed = layout
        for index in changed.controls.indices {
            changed.controls[index].placement = changed.controls[index].placement.mirrored()
        }
        return changed
    }

    private static func inside(_ frame: CGRect, _ area: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        return frame
    }
}
