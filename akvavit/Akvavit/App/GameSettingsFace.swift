// SPDX-License-Identifier: GPL-3.0-or-later
//
// The popup's underside: the game's settings. Done tips the card back.
// Installed games get Check and repair at the top.

import AkvavitKit
import SwiftUI

struct GameSettingsFace: View {
    let game: Game
    let layout: PopupLayout
    /// The card's final size.
    let size: CGSize
    let model: GamePopupModel
    @Bindable private var store = GameSettingsStore.shared
    private static let fade: CGFloat = 32
    private let layouts = ControlLayoutStore.shared

    /// The game's layout; one deleted since reads as the default.
    private var layoutChoice: Binding<String> {
        Binding(get: {
            store[game.id].controlLayout.flatMap { layouts.layout(id: $0)?.id } ?? BuiltInLayouts.gameDefault.id
        }, set: { id in
            store[game.id].controlLayout = id == BuiltInLayouts.gameDefault.id ? nil : id
        })
    }

    var body: some View {
        // Full spacing only on the inner display in landscape.
        let wide = layout == .wide && size.width >= 700
        VStack(alignment: .leading, spacing: wide ? 18 : 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Game settings")
                        .font(.quicksand(wide ? 26 : 22, .bold, relativeTo: .title))
                        .accessibilityAddTraits(.isHeader)
                    Text(game.name)
                        .font(.quicksand(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.cardSecondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Done") { model.hideSettings() }
                    .font(.quicksand(16, .bold, relativeTo: .body))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Theme.accent, in: .capsule)
                    .buttonStyle(.plain)
            }

            // The rows scroll when they don't fit (the outer display); the
            // title and Done stay. A soft fade at the bottom shows there is
            // more; the last row can scroll clear of it.
            ScrollView {
                VStack(alignment: .leading, spacing: wide ? 18 : 10) {
                    rows
                }
                .padding(.bottom, Self.fade)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
        }
        .foregroundStyle(Theme.cardText)
        .padding(.horizontal, wide ? 32 : 20)
        .padding(.vertical, wide ? 28 : 20)
    }

    @ViewBuilder
    private var rows: some View {
        SettingRow("Controls", detail: "The on-screen controls over the game. Make and change layouts in the Controls tab.") {
            Menu {
                Picker("Controls", selection: layoutChoice) {
                    Section("Built in") {
                        ForEach(layouts.builtIns) { Text($0.name).tag($0.id) }
                    }
                    if !layouts.yours.isEmpty {
                        Section("Yours") {
                            ForEach(layouts.yours) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            } label: {
                MenuLabel(layouts.layout(id: layoutChoice.wrappedValue)?.name ?? BuiltInLayouts.gameDefault.name)
            }
        }
        SettingRow("Screen size", detail: "The size of the Windows screen the game runs on.") {
            Menu {
                Picker("Screen size", selection: $store[game.id].screenSize) {
                    ForEach(GameSettings.ScreenSize.allCases, id: \.self) { Text($0.label) }
                }
            } label: {
                MenuLabel(store[game.id].screenSize.label)
            }
        }
        if game.installed {
            RepairRow(game: game)
        }
        SettingRow("Performance bar",
                   detail: "Frames per second and how busy the processor and graphics are, in the top-left corner.") {
            Toggle("Performance bar", isOn: $store[game.id].performanceBar)
                .labelsHidden()
                .tint(Theme.accent)
        }
        SettingRow("Reduced-precision x87",
                   detail: "Much faster Direct3D 8 games. Off computes floating point exactly, slowly.") {
            Toggle("Reduced-precision x87", isOn: $store[game.id].reducedPrecisionX87)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    var detailIsProblem = false
    @ViewBuilder let control: Control

    init(_ title: String, detail: String, detailIsProblem: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.detailIsProblem = detailIsProblem
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.quicksand(17, .bold, relativeTo: .body))
                Text(detail)
                    .font(.quicksand(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(detailIsProblem ? Theme.destructive : Theme.cardSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.tile, in: .rect(cornerRadius: 18))
    }
}

/// Checks every file of the game and fetches the damaged or missing ones
/// (and brings it to the newest version). Its progress shows in the row,
/// and on the front above Play.
private struct RepairRow: View {
    let game: Game

    var body: some View {
        let download = Downloads.shared[game.id]
        let failure: String? = if case .failed(let reason) = download?.phase { reason } else { nil }
        let running = download != nil && failure == nil
        SettingRow("Check and repair",
                   detail: failure ?? "Checks the game's files and downloads any that are damaged or missing.",
                   detailIsProblem: failure != nil) {
            if running, let download {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(Self.status(download))
                        .monospacedDigit()
                }
                .font(.quicksand(15, .bold, relativeTo: .body))
                .foregroundStyle(Theme.cardSecondaryText)
                .frame(minHeight: 40)
            } else {
                Button {
                    Downloads.shared.repair(game.id)
                } label: {
                    MenuLabel(failure == nil ? "Check" : "Try again", chevron: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func status(_ download: GameDownload) -> String {
        switch download.phase {
        case .waiting: "Waiting"
        case .checking: "Checking \(Int(download.fraction * 100)) %"
        case .downloading: "Downloading \(Int(download.fraction * 100)) %"
        default: "Working"
        }
    }
}

private struct MenuLabel: View {
    let text: String
    /// A menu's chevron; a plain button has none.
    var chevron = true

    init(_ text: String, chevron: Bool = true) {
        self.text = text
        self.chevron = chevron
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
            }
        }
        .font(.quicksand(15, .bold, relativeTo: .body))
        .foregroundStyle(Theme.outlineText)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.outline, lineWidth: 2)
        }
    }
}
