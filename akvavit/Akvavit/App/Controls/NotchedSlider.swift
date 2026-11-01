// SPDX-License-Identifier: GPL-3.0-or-later
//
// A slider that stops only at its notches (the canvas's sliders for sizes,
// speeds and the grid): a track filled up to the knob, a mark at each notch.

import AkvavitKit
import SwiftUI

struct NotchedSlider: View {
    /// The value at each notch, left to right.
    let values: [Double]
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let span = max(geometry.size.width - 4, 1)
            let x = position(of: index, span: span)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.outline).frame(height: 4)
                Capsule().fill(Theme.controlsColors.tint).frame(width: x + 2, height: 4)
                ForEach(values.indices, id: \.self) { notch in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.notch)
                        .frame(width: 4, height: 8)
                        .offset(x: position(of: notch, span: span))
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: Theme.shadow.opacity(0.3), radius: 3, y: 2)
                    .offset(x: x + 2 - 11)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let notch = Int((drag.location.x / span * CGFloat(values.count - 1)).rounded())
                let chosen = values[min(max(notch, 0), values.count - 1)]
                guard chosen != value else { return }
                value = chosen
                // A tick at each notch, unless haptics are off on the Controls tab.
                if ControlLayoutStore.shared.haptics { UISelectionFeedbackGenerator().selectionChanged() }
            })
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { direction in
            let notch = direction == .increment ? index + 1 : index - 1
            if values.indices.contains(notch) { value = values[notch] }
        }
    }

    private static let notch = Color(light: 0x20243A, dark: 0xFFFFFF, alpha: 0.25, darkAlpha: 0.3)

    /// The notch nearest the value.
    private var index: Int {
        values.indices.min { abs(values[$0] - value) < abs(values[$1] - value) } ?? 0
    }

    private func position(of notch: Int, span: CGFloat) -> CGFloat {
        values.count > 1 ? CGFloat(notch) / CGFloat(values.count - 1) * span : 0
    }
}
