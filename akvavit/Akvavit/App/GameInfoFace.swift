// SPDX-License-Identifier: GPL-3.0-or-later
//
// The popup's info side: the cover, the title, the facts, Play, and below it
// Game settings and Uninstall (which asks on the card itself). For a game that
// isn't installed (Get games): Install, then the download's progress; once
// installed it turns into the full side. An update or a check and repair runs
// in Play's place, as a progress bar. A newer version shows as Update: above
// Play for GOG (a GOG game can still be played as it is), in Play's place for
// Steam (Valve's client would update it at start anyway).

import AkvavitKit
import SwiftUI

struct GameInfoFace: View {
    let game: Game
    let layout: PopupLayout
    /// The card's final size.
    let size: CGSize
    let model: GamePopupModel

    var body: some View {
        ZStack {
            switch layout {
            case .wide: wide
            case .tall: tall
            }
            if let confirming = model.confirming {
                CardConfirmation(game: game, confirmation: confirming, width: min(380, size.width - 40), model: model)
            }
        }
        .foregroundStyle(Theme.cardText)
    }

    /// Landscape on the outer display: the same layout, smaller.
    private var small: Bool { size.width < 700 }

    private var wide: some View {
        let padding: CGFloat = small ? 20 : 24
        let coverWidth = min((size.height - 2 * padding) * 2 / 3, size.width * 0.36)
        return HStack(alignment: .top, spacing: small ? 20 : 28) {
            cover(width: coverWidth, height: coverWidth * 3 / 2, titleSize: small ? 16 : 22, radius: 16)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        title(size: small ? 22 : 28)
                        SourceChip(source: game.source)
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                    CloseButton { model.close() }
                }
                FactsRow(game: game, compact: small)
                    .padding(.top, small ? 18 : 26)
                Spacer(minLength: 16)
                buttons(compact: small)
            }
        }
        .padding(padding)
    }

    private var tall: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                cover(width: 132, height: 198, titleSize: 13, radius: 14)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer(minLength: 0)
                        CloseButton { model.close() }
                    }
                    title(size: 22)
                    SourceChip(source: game.source)
                }
            }
            FactsRow(game: game, compact: true)
                .padding(.top, 22)
            Spacer(minLength: 16)
            buttons(compact: true)
        }
        .padding(20)
    }

    private func cover(width: CGFloat, height: CGFloat, titleSize: CGFloat, radius: CGFloat) -> some View {
        // Decoded at the card's height, the same image as the flight's cover.
        CoverArt(game: game, titleSize: titleSize, showsBadge: false, loadHeight: size.height)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: radius))
            .shadow(color: Theme.shadow.opacity(0.35), radius: 15, y: 14)
            .accessibilityHidden(true)
    }

    private func title(size: CGFloat) -> some View {
        Text(game.name)
            .font(.quicksand(size, .bold, relativeTo: .title))
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        if game.installed {
            actions(compact: compact)
        } else {
            InstallButton(game: game, compact: compact, model: model)
        }
    }

    private func actions(compact: Bool) -> some View {
        let play = model.play
        let blocked = play.blocked
        let download = Downloads.shared[game.id]
        let separateUpdate = game.source == .gog && download == nil && (game.updateAvailable || game.updateUnfinished)
        let updateInPlace = download != nil || (game.source == .steam && game.updateAvailable)
        // A game half way between two versions doesn't start.
        let unfinished = separateUpdate && game.updateUnfinished ? "The update didn't finish. Finish it to play." : nil
        let held = blocked ?? unfinished
        return VStack(spacing: compact ? 10 : 12) {
            if separateUpdate {
                InstallButton(game: game, compact: compact, model: model)
            }
            if let note = play.problem ?? held, !updateInPlace {
                Text(note)
                    .font(.quicksand(compact ? 13 : 14, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if updateInPlace {
                InstallButton(game: game, compact: compact, model: model)
            } else {
                playButton(play, held: held, compact: compact)
            }
            HStack(spacing: compact ? 10 : 12) {
                Button {
                    model.showSettings()
                } label: {
                    Label("Game settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(OutlineButtonStyle(fontSize: compact ? 15 : 16))
                Button {
                    model.ask(.uninstall)
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(OutlineButtonStyle(fontSize: compact ? 15 : 16, destructive: true))
            }
        }
    }

    private func playButton(_ play: PlayStart, held: String?, compact: Bool) -> some View {
        Button {
            Task { await play.play(game) }
        } label: {
            if let step = play.step {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(step)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                Label("Play", systemImage: "play.fill")
            }
        }
        .buttonStyle(FilledButtonStyle(color: Theme.accent, height: compact ? 56 : 58,
                                       fontSize: compact ? 19 : 20))
        .disabled(play.busy || held != nil)
        .opacity(held != nil ? 0.55 : 1)
    }
}

private struct FactsRow: View {
    let game: Game
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            fact("Playtime", GameFacts.playtime(game.playtimeMinutes))
            fact("Released", game.releaseYear.map(String.init) ?? "—")
            if game.installed {
                fact("Size on disk", GameFacts.size(game.sizeOnDisk))
            } else {
                fact("Size", GameFacts.size(game.installSize ?? game.downloadSize))
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.quicksand(compact ? 11 : 12, .bold, relativeTo: .caption))
                .tracking(0.4)
                .foregroundStyle(Theme.cardSecondaryText)
            Text(value)
                .font(.quicksand(compact ? 16 : 20, .bold, relativeTo: .title3))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 12 : 14)
        .background(game.installed ? Theme.tile : Theme.installTile, in: .rect(cornerRadius: compact ? 14 : 16))
        .accessibilityElement(children: .combine)
    }
}

/// Install, then the download's progress in its place, with its speed below
/// and a button that cancels it; a failed download says why and offers to
/// try again. For an installed game the same as Update; stopping an update
/// deletes nothing (Update goes on from there).
private struct InstallButton: View {
    let game: Game
    let compact: Bool
    let model: GamePopupModel

    var body: some View {
        let height: CGFloat = compact ? 56 : 58
        let fontSize: CGFloat = compact ? 19 : 20
        let teal = Theme.getGamesColors.tint
        if let download = Downloads.shared[game.id] {
            if case .failed(let reason) = download.phase {
                VStack(spacing: compact ? 10 : 12) {
                    Text(reason)
                        .font(.quicksand(compact ? 13 : 14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            Downloads.shared.install(game.id)
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(FilledButtonStyle(color: teal, height: height, fontSize: fontSize))
                        cancelButton(height: height)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        ProgressBar(fraction: !download.sharedFiles && (download.phase == .downloading || download.phase == .finishing) ? download.fraction : 0,
                                    label: Self.label(download), height: height, fontSize: compact ? 17 : 18)
                        cancelButton(height: height)
                    }
                    // In Play's place (an installed game) the bar keeps Play's
                    // height, so nothing on the card moves.
                    if !game.installed {
                        Text(Self.detail(download))
                            .font(.quicksand(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Theme.cardSecondaryText)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                    }
                }
            }
        } else if game.partiallyDownloaded {
            HStack(spacing: 10) {
                Button {
                    Downloads.shared.install(game.id)
                } label: {
                    Label("Resume download", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(FilledButtonStyle(color: teal, height: height, fontSize: fontSize))
                cancelButton(height: height)
            }
        } else if game.installed {
            Button {
                Downloads.shared.install(game.id)
            } label: {
                Label(game.updateUnfinished ? "Finish update" : "Update", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(FilledButtonStyle(color: teal, height: height, fontSize: fontSize))
        } else {
            Button {
                Downloads.shared.install(game.id)
            } label: {
                Label("Install", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(FilledButtonStyle(color: teal, height: height, fontSize: fontSize))
        }
    }

    private func cancelButton(height: CGFloat) -> some View {
        Button {
            if game.installed {
                Downloads.shared.cancelDownload(game.id)
            } else {
                model.ask(.cancelDownload)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .frame(width: height, height: height)
        }
        .buttonStyle(OutlineButtonStyle(height: height, destructive: true))
        .frame(width: height)
        .accessibilityLabel(game.installed ? "Stop" : "Cancel download")
    }

    /// Speed and amount, under the bar: "12.3 MB/s · 1.2 of 22 GB".
    static func detail(_ download: GameDownload) -> String {
        guard download.phase == .downloading, !download.sharedFiles, download.totalBytes > 0 else { return " " }
        var parts: [String] = []
        if download.bytesPerSecond > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(download.bytesPerSecond), countStyle: .file) + "/s")
        }
        parts.append(GameFacts.size(Int64(download.doneBytes)) + " of " + GameFacts.size(Int64(download.totalBytes)))
        return parts.joined(separator: " · ")
    }

    static func label(_ download: GameDownload) -> String {
        if download.sharedFiles, download.phase != .waiting { return "Checking Steam's shared files…" }
        return switch download.phase {
        case .waiting: "Waiting for another download"
        case .preparing: "Preparing…"
        case .checking: "Checking files…"
        case .downloading: "Downloading… \(Int(download.fraction * 100))%"
        case .finishing: "Finishing…"
        case .failed: "Failed"
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let label: String
    let height: CGFloat
    let fontSize: CGFloat

    var body: some View {
        let teal = Theme.getGamesColors.tint
        RoundedRectangle(cornerRadius: 18)
            .fill(teal.opacity(0.16))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    teal.frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        .animation(.linear(duration: 0.15), value: fraction)
                }
            }
            .overlay {
                Text(label)
                    .font(.quicksand(fontSize, .bold, relativeTo: .headline))
                    .foregroundStyle(fraction > 0.5 ? Color.white : Theme.cardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
            }
            .clipShape(.rect(cornerRadius: 18))
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(Text("\(Int(fraction * 100)) percent"))
    }
}

private struct SourceChip: View {
    let source: Game.Source

    var body: some View {
        Label {
            Text(source.displayName)
        } icon: {
            StoreLogo(source: source, size: 14).accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .font(.quicksand(13, .bold, relativeTo: .caption))
        .foregroundStyle(Theme.chipText)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.chip, in: .capsule)
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.chipText)
                .frame(width: 44, height: 44)
                .background(Theme.chip, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// Asks on the card itself before something that can't be undone: an
/// uninstall, or cancelling a download (what it downloaded is deleted).
private struct CardConfirmation: View {
    let game: Game
    let confirmation: GamePopupModel.Confirmation
    let width: CGFloat
    let model: GamePopupModel

    private var title: String {
        switch confirmation {
        case .uninstall: "Uninstall \(game.name)?"
        case .cancelDownload: "Cancel the download?"
        }
    }

    private var message: String {
        switch confirmation {
        case .uninstall:
            (game.sizeOnDisk.map { "This deletes its \(GameFacts.size($0)) of game files." } ?? "This deletes its game files.")
                + " You can install it again from Get games."
        case .cancelDownload:
            "What has been downloaded of \(game.name) so far is deleted."
        }
    }

    private var keepLabel: String { confirmation == .uninstall ? "Cancel" : "Keep downloading" }
    private var actionLabel: String { confirmation == .uninstall ? "Uninstall" : "Cancel download" }

    var body: some View {
        let working = model.confirmedWorking
        ZStack {
            Theme.cardDim
                .contentShape(.rect)
                .onTapGesture { model.dismissConfirmation() }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.quicksand(20, .bold, relativeTo: .title3))
                Text(message)
                if let error = model.confirmError {
                    Text(error)
                        .font(.quicksand(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.destructive)
                }
                HStack(spacing: 10) {
                    Button(keepLabel) { model.dismissConfirmation() }
                        .buttonStyle(OutlineButtonStyle(fontSize: 16, height: 46))
                    Button {
                        Task { await model.confirm() }
                    } label: {
                        if working {
                            ProgressView().tint(.white)
                        } else {
                            Text(actionLabel)
                        }
                    }
                    .buttonStyle(FilledButtonStyle(color: Theme.destructiveFill, height: 46, fontSize: 16))
                    .accessibilityLabel(working ? "Working" : actionLabel)
                }
                .disabled(working)
                .padding(.top, 8)
            }
            .font(.quicksand(15, .semibold, relativeTo: .body))
            .foregroundStyle(Theme.cardText)
            .padding(24)
            .frame(width: width)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .shadow(color: Theme.shadow.opacity(0.35), radius: 25, y: 20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: - Button styles

struct FilledButtonStyle: ButtonStyle {
    let color: Color
    var height: CGFloat = 58
    var fontSize: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(fontSize, .bold, relativeTo: .headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(color, in: .rect(cornerRadius: height >= 54 ? 18 : 14))
            .shadow(color: color.opacity(0.35), radius: 12, y: 10)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 16
    var height: CGFloat = 48
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.quicksand(fontSize, .bold, relativeTo: .body))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(destructive ? Theme.destructive : Theme.outlineText)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(.rect)
            .overlay {
                RoundedRectangle(cornerRadius: height >= 48 ? 16 : 14)
                    .strokeBorder(destructive ? Theme.destructiveOutline : Theme.outline, lineWidth: 2)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Facts about a game, in words.
enum GameFacts {
    static func playtime(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        switch minutes {
        case 0: return "None"
        case ..<60: return "\(minutes) min"
        case ..<600: return (Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...1))) + " h"
        default: return "\(minutes / 60) h"
        }
    }

    /// GB with one decimal, MB whole: "22.2 GB", "2.4 GB", "669 MB".
    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let gigabytes = Double(bytes) / 1e9
        if gigabytes >= 1 { return gigabytes.formatted(.number.precision(.fractionLength(1))) + " GB" }
        return "\(max(1, Int((Double(bytes) / 1e6).rounded()))) MB"
    }
}
