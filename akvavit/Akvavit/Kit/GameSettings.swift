// SPDX-License-Identifier: GPL-3.0-or-later
//
// Each game's own settings (the popup's settings side), kept in one file and
// used when the game starts.

import Foundation
import Observation

public struct GameSettings: Codable, Equatable, Sendable {
    public enum ScreenSize: String, Codable, CaseIterable, Sendable {
        /// The display's shape, 768 pixels high.
        case fit
        case size1024x768
        case size800x600
        case size640x480

        public var label: String {
            switch self {
            case .fit: "Fit the display"
            case .size1024x768: "1024 × 768"
            case .size800x600: "800 × 600"
            case .size640x480: "640 × 480"
            }
        }

        /// The size in pixels; `fitting` for `.fit`.
        public func pixels(fitting: (width: Int, height: Int)) -> (width: Int, height: Int) {
            switch self {
            case .fit: fitting
            case .size1024x768: (1024, 768)
            case .size800x600: (800, 600)
            case .size640x480: (640, 480)
            }
        }
    }

    public enum Controls: String, Codable, CaseIterable, Sendable {
        case touchAsMouse

        public var label: String { "Touch as mouse" }
    }

    public var reducedPrecisionX87 = true
    public var screenSize = ScreenSize.fit
    public var controls = Controls.touchAsMouse

    public init() {}
}

@MainActor @Observable
public final class GameSettingsStore {
    public static let shared = GameSettingsStore()

    private var byGame: [String: GameSettings] = [:]
    @ObservationIgnored private var saving: Task<Void, Never>?

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let stored = try? JSONDecoder().decode([String: GameSettings].self, from: data) {
            byGame = stored
        }
    }

    /// A game's settings (by `Game.id`); defaults for a game never changed.
    public subscript(gameID: String) -> GameSettings {
        get { byGame[gameID] ?? GameSettings() }
        set {
            guard newValue != self[gameID] else { return }
            byGame[gameID] = newValue == GameSettings() ? nil : newValue
            save()
        }
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("akvavit-game-settings.json")
    }

    /// Writes the file atomically, off the main thread, one write after another.
    private func save() {
        let settings = byGame
        let url = Self.fileURL
        let previous = saving
        saving = Task.detached(priority: .utility) {
            await previous?.value
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(settings) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension LaunchConfig {
    /// A game's start with its settings. `fitting` is the screen size that
    /// fits the display, for `.fit`.
    public init(game: Game, settings: GameSettings, fitting: (width: Int, height: Int)) {
        let size = settings.screenSize.pixels(fitting: fitting)
        switch game.source {
        case .steam:
            self.init(program: .steam(appID: game.appID), screenWidth: size.width, screenHeight: size.height,
                      reducedPrecisionX87: settings.reducedPrecisionX87)
        case .gog:
            // GOG games can't be installed yet (GOG step 2), so Play never
            // reaches this; their start comes in step 3.
            self.init(program: .desktop(), screenWidth: size.width, screenHeight: size.height,
                      reducedPrecisionX87: settings.reducedPrecisionX87)
        }
    }
}
