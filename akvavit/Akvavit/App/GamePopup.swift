// SPDX-License-Identifier: GPL-3.0-or-later
//
// A game's popup. The tapped cover lifts, then turns half a turn (around the
// vertical axis) while it grows into the popup; its back is the game's info.
// Game settings are on the popup's underside: it tips over (around the
// horizontal axis) to show them.
//
// One card does it all, laid out once at its final size. Three animated values
// drive it (open, lift, tip); each frame picks the face that points at the
// viewer and turns it with one 3D transform. With Reduce Motion it crossfades.

import QuartzCore
import SwiftUI

@MainActor @Observable
final class GamePopupModel {
    enum Phase { case closed, opening, open, closing }

    private(set) var game: PlaceholderGame?
    private(set) var phase = Phase.closed
    /// The cover's frame in global coordinates, kept up to date while open.
    var sourceFrame = CGRect.zero
    /// False once the cover has scrolled out of its grid (cells are lazy).
    var sourceVisible = true
    /// The popup layer's frame in global coordinates.
    var layerFrame = CGRect.zero

    // Animated: 0…1 each.
    private(set) var open = 0.0
    private(set) var lift = 0.0
    private(set) var tip = 0.0
    private(set) var backdrop = 0.0

    /// Fade in place instead of flying (Reduce Motion, or the cover is gone).
    private(set) var crossfade = false
    private(set) var settingsShown = false
    var confirmingUninstall = false
    /// Changes to rebuild the card at its current values, dropping animations.
    private(set) var cardID = 0

    // Spike only: game settings, until step 3 keeps them per game.
    var x87 = true
    var screenSize = "Fit the display"

    private var generation = 0
    private var began = false
    private var tipping = false
    private var reduceMotion = false

    static let flipCurve = (0.45, 0.05, 0.25, 1.0)
    static func flip(duration: Double) -> Animation {
        .timingCurve(flipCurve.0, flipCurve.1, flipCurve.2, flipCurve.3, duration: duration)
    }
    private static let fade = Animation.easeInOut(duration: 0.3)

    func isShowing(_ game: PlaceholderGame) -> Bool {
        phase != .closed && self.game?.id == game.id
    }

    func show(_ game: PlaceholderGame, from frame: CGRect, reduceMotion: Bool) {
        guard phase == .closed else { return }
        generation += 1
        self.game = game
        self.reduceMotion = reduceMotion
        sourceFrame = frame
        sourceVisible = true
        open = 0
        lift = 0
        tip = 0
        backdrop = 0
        crossfade = reduceMotion
        settingsShown = false
        confirmingUninstall = false
        began = false
        phase = .opening
        // The card appears at the cover first; begin() moves it once it is on screen.
    }

    /// Called when the card is on screen.
    func begin() {
        guard phase == .opening, !began else { return }
        began = true
        let gen = generation
        if crossfade {
            withAnimation(Self.fade) {
                open = 1
                backdrop = 1
            } completion: { self.opened(gen) }
            return
        }
        withAnimation(.easeOut(duration: 0.17)) { lift = 1 } completion: {
            guard gen == self.generation else { return }
            withAnimation(.easeOut(duration: 0.32)) { self.backdrop = 1 }
            withAnimation(Self.flip(duration: 0.9)) {
                self.open = 1
                self.lift = 0
            } completion: { self.opened(gen) }
        }
    }

    private func opened(_ gen: Int) {
        guard gen == generation, phase == .opening else { return }
        phase = .open
    }

    func close() {
        guard phase == .open, !tipping else { return }
        generation += 1
        let gen = generation
        phase = .closing
        confirmingUninstall = false
        settingsShown = false
        tip = 0
        withAnimation(.easeOut(duration: 0.32)) { backdrop = 0 }
        // Back into the cover, if it is still on screen; otherwise fade out.
        let onScreen = layerFrame.intersection(sourceFrame).height >= sourceFrame.height / 2
        if reduceMotion || !sourceVisible || !onScreen {
            crossfade = true
            withAnimation(Self.fade) { open = 0 } completion: { self.finish(gen) }
            return
        }
        crossfade = false
        withAnimation(Self.flip(duration: 0.72)) {
            open = 0
            lift = 1
        } completion: {
            guard gen == self.generation else { return }
            withAnimation(.easeIn(duration: 0.17)) { self.lift = 0 } completion: { self.finish(gen) }
        }
    }

    private func finish(_ gen: Int) {
        guard gen == generation, phase == .closing else { return }
        game = nil
        phase = .closed
        crossfade = false
    }

    func showSettings() { setSettings(true) }
    func hideSettings() { setSettings(false) }

    private func setSettings(_ shown: Bool) {
        guard phase == .open, !tipping, settingsShown != shown else { return }
        settingsShown = shown
        confirmingUninstall = false
        tipping = true
        let gen = generation
        withAnimation(crossfade ? Self.fade : Self.flip(duration: 0.9)) {
            tip = shown ? 1 : 0
        } completion: {
            if gen == self.generation { self.tipping = false }
        }
    }

    /// A tap outside the card, or VoiceOver's escape: one level at a time.
    func back() {
        guard phase == .open, !tipping else { return }
        if confirmingUninstall {
            confirmingUninstall = false
        } else if settingsShown {
            hideSettings()
        } else {
            close()
        }
    }

    /// The display changed (fold, unfold, rotation): finish at once and re-centre.
    func layoutChanged() {
        guard phase != .closed else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch phase {
            case .opening:
                generation += 1
                open = 1
                lift = 0
                backdrop = 1
                phase = .open
            case .open:
                generation += 1
                tip = settingsShown ? 1 : 0
                tipping = false
            case .closing:
                finish(generation)
            case .closed:
                break
            }
            cardID += 1
        }
    }
}

/// Where the popup goes, and which layout it has, for the display's size.
enum PopupLayout {
    /// Cover left, details right (landscape, on either display).
    case wide
    /// Cover and title on top, details below (portrait).
    case tall

    static func frame(in size: CGSize, safeArea insets: EdgeInsets) -> (CGRect, PopupLayout) {
        let safe = CGRect(x: insets.leading, y: insets.top,
                          width: size.width - insets.leading - insets.trailing,
                          height: size.height - insets.top - insets.bottom)
        let wide = safe.width > safe.height
        let width = wide ? min(760, safe.width - 28) : min(safe.width - 28, 520)
        let height = wide ? min(452, safe.height - 32) : min(safe.height - 48, 720)
        let frame = CGRect(x: safe.midX - width / 2, y: safe.midY - height / 2, width: width, height: height)
        return (frame, wide ? .wide : .tall)
    }
}

/// Above everything: the dimmed, blurred background and the card.
struct GamePopupLayer: View {
    let model: GamePopupModel
    let safeArea: EdgeInsets

    var body: some View {
        GeometryReader { proxy in
            let layerFrame = proxy.frame(in: .global)
            if let game = model.game {
                let (target, layout) = PopupLayout.frame(in: proxy.size, safeArea: safeArea)
                let source = model.sourceFrame.offsetBy(dx: -layerFrame.minX, dy: -layerFrame.minY)
                ZStack(alignment: .topLeading) {
                    // Catches taps while the backdrop is still transparent.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { model.back() }
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Theme.dim)
                        .opacity(model.backdrop)
                        .allowsHitTesting(false)
                    FlipCard(game: game, source: source, target: target, layout: layout,
                             crossfade: model.crossfade, model: model,
                             open: model.open, lift: model.lift, tip: model.tip)
                        .id(model.cardID)
                        .onAppear { model.begin() }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.layerFrame = $0 }
    }
}

private enum Face { case cover, info, settings }

private struct FlipCard: View, Animatable {
    let game: PlaceholderGame
    let source: CGRect
    let target: CGRect
    let layout: PopupLayout
    let crossfade: Bool
    let model: GamePopupModel
    var open: Double
    var lift: Double
    var tip: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(open, lift), tip) }
        set {
            open = newValue.first.first
            lift = newValue.first.second
            tip = newValue.second
        }
    }

    private var coverRadius: CGFloat { layout == .wide ? 12 : 10 }

    var body: some View {
        Group {
            if crossfade {
                ZStack {
                    face(.info, size: target.size, radius: 28).opacity(1 - tip)
                    face(.settings, size: target.size, radius: 28).opacity(tip)
                }
                .opacity(open)
                .frame(width: target.width, height: target.height)
                .position(x: target.midX, y: target.midY)
                .allowsHitTesting(open == 1 && (tip == 0 || tip == 1))
            } else {
                let frame = interpolate(source, target, open)
                let face: Face = open < 1 ? (open < 0.5 ? .cover : .info) : (tip < 0.5 ? .info : .settings)
                self.face(face, size: frame.size, radius: coverRadius + (28 - coverRadius) * open)
                    .projectionEffect(projection(of: face, size: frame.size))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(open == 1 && (tip == 0 || tip == 1))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { model.back() }
    }

    @ViewBuilder
    private func face(_ face: Face, size: CGSize, radius: CGFloat) -> some View {
        switch face {
        case .cover:
            CoverArt(game: game, titleSize: layout == .wide ? 15 : 12, showsBadge: false)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: radius))
                .shadow(color: Theme.shadow.opacity(0.28 + 0.17 * lift), radius: 13 + 17 * lift, y: 12 + 18 * lift)
                .transition(.identity)
        case .info:
            CardFace(size: size, finalSize: target.size, radius: radius) {
                GameInfoFace(game: game, layout: layout, size: target.size, model: model)
            }
            .transition(.identity)
        case .settings:
            CardFace(size: size, finalSize: target.size, radius: radius) {
                GameSettingsFace(game: game, layout: layout, size: target.size, model: model)
            }
            .transition(.identity)
        }
    }

    /// The card's turn as one 3D transform about its centre. Each back face is
    /// turned beforehand, so it reads the right way round once the card has
    /// turned: the info side by half a turn around the vertical axis, the
    /// settings side (behind the info side, around the horizontal axis) by half
    /// a turn in the plane.
    private func projection(of face: Face, size: CGSize) -> ProjectionTransform {
        var m = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        switch face {
        case .cover: break
        case .info: m = CATransform3DConcat(m, CATransform3DMakeRotation(.pi, 0, 1, 0))
        case .settings: m = CATransform3DConcat(m, CATransform3DMakeRotation(.pi, 0, 0, 1))
        }
        let scale = 1 + 0.06 * lift
        m = CATransform3DConcat(m, CATransform3DMakeScale(scale, scale, 1))
        m = CATransform3DConcat(m, CATransform3DMakeRotation(8 * .pi / 180 * lift, 1, 0, 0))
        m = CATransform3DConcat(m, CATransform3DMakeRotation(.pi * tip, 1, 0, 0))
        m = CATransform3DConcat(m, CATransform3DMakeRotation(-.pi * open, 0, 1, 0))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 1400
        m = CATransform3DConcat(m, perspective)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0))
        return ProjectionTransform(m)
    }

    private func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}

/// A side of the card: its content laid out at the final size, scaled into
/// the card's current size, so the text never reflows while the card grows.
private struct CardFace<Content: View>: View {
    let size: CGSize
    let finalSize: CGSize
    let radius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let scale = min(size.width / finalSize.width, size.height / finalSize.height)
        content
            .frame(width: finalSize.width, height: finalSize.height)
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
            .background(Theme.card)
            .clipShape(.rect(cornerRadius: radius))
            .shadow(color: Theme.shadow.opacity(0.35), radius: 40, y: 30)
    }
}
