// SPDX-License-Identifier: GPL-3.0-or-later
//
// The loading screen (the canvas's "Loading A: cover and steps", chosen by the
// user): while a game starts, its cover beside a checklist of what is
// happening, on the app's own background. When a window may need an answer
// (an installer, Steam), a card says so and can show Windows' screen until
// that window closes. What happens comes from StartProgress; this file only
// draws it, so the look can change on its own.
//
// It is drawn in GameOverlay's window, above Windows' screen (ControlsOverlay),
// and lets touches through except on its button (LoadingTouches): four
// fingers still open the test menu, and nothing reaches the game meanwhile
// (GameSurfaceView).

import AkvavitKit
import SwiftUI

struct LoadingScreen: View {
    /// The game starting; nil for a start without one (the test screens).
    let game: Game?
    let title: String
    private let progress = StartProgress.shared

    var body: some View {
        GeometryReader { geometry in
            // Laid out at the board's size, scaled down to fit smaller displays.
            let size = CGSize(width: 711, height: 485)
            let scale = min(1, (geometry.size.width - 32) / size.width, (geometry.size.height - 32) / size.height)
            ZStack {
                if let asking = progress.asking {
                    AskingCard(game: game, asking: asking, show: progress.showAsking)
                        .transition(.opacity)
                } else {
                    stepsCard
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    if progress.failedBeforeSession || progress.stopped {
                        // Play stopped before Windows started: back to the game's
                        // popup. Windows stopped: it starts once per app run.
                        Button(progress.stopped ? "Close Akvavit" : "Back") {
                            if progress.stopped { exit(0) } else { progress.back() }
                        }
                            .buttonStyle(FilledButtonStyle(color: Theme.accent, height: 46, fontSize: 16))
                            .frame(width: 200)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { LoadingTouches.button = $0 }
                            .onDisappear { LoadingTouches.button = nil }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, max(8, (geometry.size.height - size.height * scale) / 2 - 62))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.2), value: progress.asking)
        }
        .background { ThemeBackground().ignoresSafeArea().allowsHitTesting(false) }
    }

    private var stepsCard: some View {
        HStack(alignment: .top, spacing: 32) {
            if let game {
                CoverArt(game: game, loadHeight: 425)
                    .frame(width: 282, height: 425)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: Theme.shadow.opacity(0.38), radius: 17, y: 16)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Starting")
                    .font(.quicksand(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.cardSecondaryText)
                Text(title)
                    .font(.quicksand(30, .bold, relativeTo: .title))
                    .foregroundStyle(Theme.cardText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                    .padding(.bottom, 26)
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(progress.steps, id: \.self) { step in
                        StepRow(step: step, line: progress.lines[step])
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(30)
        .background(Theme.card, in: .rect(cornerRadius: 28))
        .shadow(color: Theme.shadow.opacity(0.3), radius: 40, y: 30)
        .accessibilityElement(children: .combine)
    }
}

/// Where the loading screen's button is, in the window: the only touches
/// the overlay takes while the loading screen covers the game.
@MainActor
enum LoadingTouches {
    static var button: CGRect?
}

private struct StepRow: View {
    let step: StartProgress.Step
    let line: StartProgress.Line?

    var body: some View {
        let status = line?.status ?? .waiting
        HStack(alignment: .top, spacing: 14) {
            StepMark(status: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.quicksand(16, .bold, relativeTo: .body))
                    .foregroundStyle(status == .waiting ? Theme.cardSecondaryText : Theme.cardText)
                if let detail = line?.detail {
                    Text(detail)
                        .font(.quicksand(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(status == .failed ? Theme.destructive : Theme.cardSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 1)
        }
    }

    private var title: String {
        switch step {
        case .jit: "JIT"
        case .clientFiles: "Steam's client files"
        case .windows: "Windows"
        case .installs: "One-time installs"
        case .steam: "Steam"
        case .game: "The game"
        }
    }
}

/// Done: a tick. Now: a turning ring. Waiting: an empty ring. Failed: a mark.
private struct StepMark: View {
    let status: StartProgress.Status

    var body: some View {
        ZStack {
            switch status {
            case .done:
                // Pops in when the step is done.
                Circle().fill(Theme.accent)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            case .now:
                Spinner()
            case .waiting:
                Circle().strokeBorder(Theme.outline, lineWidth: 2)
            case .failed:
                Circle().fill(Theme.destructiveFill)
                    .overlay {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 22, height: 22)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: status)
        .accessibilityHidden(true)
    }
}

/// A turning ring, animated by Core Animation: it goes on turning while the
/// app itself is paused (the debugger stops the app's process for moments
/// while JIT turns on and Windows prepares its memory).
private struct Spinner: UIViewRepresentable {
    func makeUIView(context: Context) -> SpinnerView { SpinnerView() }
    func updateUIView(_ view: SpinnerView, context: Context) {}

    final class SpinnerView: UIView {
        private let track = CAShapeLayer()
        private let arc = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            for layer in [track, arc] {
                layer.fillColor = UIColor.clear.cgColor
                layer.lineWidth = 3
                layer.lineCap = .round
                self.layer.addSublayer(layer)
            }
            arc.strokeEnd = 0.28
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5)).cgPath
            for layer in [track, arc] {
                layer.frame = bounds
                layer.path = ring
            }
            colour()
        }

        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            colour()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, arc.animation(forKey: "turn") == nil else { return }
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = 2 * Double.pi
            turn.duration = 0.9
            turn.repeatCount = .infinity
            turn.isRemovedOnCompletion = false
            arc.add(turn, forKey: "turn")
        }

        private func colour() {
            track.strokeColor = UIColor(Theme.outline).resolvedColor(with: traitCollection).cgColor
            arc.strokeColor = UIColor(Theme.accent).resolvedColor(with: traitCollection).cgColor
        }
    }
}

/// A window may need an answer: say which, and show Windows' screen on request.
private struct AskingCard: View {
    let game: Game?
    let asking: StartProgress.Asking
    let show: () -> Void

    var body: some View {
        HStack(spacing: 26) {
            if let game {
                CoverArt(game: game, loadHeight: 225)
                    .frame(width: 150, height: 225)
                    .clipShape(.rect(cornerRadius: 14))
                    .shadow(color: Theme.shadow.opacity(0.35), radius: 14, y: 12)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(asking.title)
                    .font(.quicksand(24, .bold, relativeTo: .title2))
                    .foregroundStyle(Theme.cardText)
                Text(asking.detail)
                    .font(.quicksand(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.cardSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show it", action: show)
                    .buttonStyle(FilledButtonStyle(color: Theme.accent, height: 46, fontSize: 16))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { LoadingTouches.button = $0 }
                    .onDisappear { LoadingTouches.button = nil }
                    .padding(.top, 8)
                Text("The loading screen comes back when the window closes.")
                    .font(.quicksand(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.cardSecondaryText)
            }
        }
        .padding(28)
        .frame(maxWidth: 601)
        .background(Theme.card, in: .rect(cornerRadius: 28))
        .shadow(color: Theme.shadow.opacity(0.3), radius: 40, y: 30)
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}
