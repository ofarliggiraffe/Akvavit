// SPDX-License-Identifier: GPL-3.0-or-later
//
// The performance bar over a game (its Game settings switch it on): frames per
// second, and how busy the processor and the graphics are, in the top-left
// corner, inside the safe area.

import AkvavitKit
import SwiftUI

struct PerformanceBar: View {
    private let progress = StartProgress.shared
    private let settings = GameSettingsStore.shared

    var body: some View {
        // Not over the loading screen: it comes with the game.
        if let game = progress.game, settings[game.id].performanceBar, !progress.covers {
            Readout()
                .padding(.leading, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
        }
    }
}

private struct Readout: View {
    private let monitor = PerformanceMonitor.shared

    var body: some View {
        let sample = monitor.sample
        Text(Self.text(sample))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: .capsule)
            .onAppear { monitor.start() }
            .onDisappear { monitor.stop() }
            .accessibilityLabel("Performance")
            .accessibilityValue(Self.text(sample))
    }

    private static func text(_ sample: PerformanceSample?) -> String {
        guard let sample else { return "– FPS · CPU –% · GPU –%" }
        let gpu = sample.gpu.map { String(format: "%.0f%%", $0) } ?? "–"
        return String(format: "%.0f FPS · CPU %.0f%% · GPU %@", sample.framesPerSecond, sample.cpu, gpu)
    }
}
