// SPDX-License-Identifier: GPL-3.0-or-later
//
// The control layouts: the built-in ones and the user's own copies, kept in
// one file, and the switch that turns off haptics for every layout.

import Foundation
import Observation

@MainActor @Observable
public final class ControlLayoutStore {
    public static let shared = ControlLayoutStore()

    public let builtIns = BuiltInLayouts.all
    public private(set) var yours: [ControlLayout] = []
    /// Off: no haptics from any control.
    public var haptics = true {
        didSet { if haptics != oldValue { save() } }
    }

    @ObservationIgnored private var saving: Task<Void, Never>?

    private struct File: Codable {
        var version = 1
        var haptics = true
        var layouts: [ControlLayout] = []

        init(haptics: Bool, layouts: [ControlLayout]) {
            self.haptics = haptics
            self.layouts = layouts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            haptics = c.value(.haptics, or: true)
            layouts = c.value(.layouts, or: [Lenient<ControlLayout>]()).compactMap(\.value)
        }
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let file = try? JSONDecoder().decode(File.self, from: data) {
            haptics = file.haptics
            yours = file.layouts.filter { !$0.isBuiltIn }
        }
    }

    public var all: [ControlLayout] { builtIns + yours }

    public func layout(id: String) -> ControlLayout? {
        all.first { $0.id == id }
    }

    /// An exact copy of `layout` as one of yours, under a name not used yet.
    @discardableResult
    public func copy(_ layout: ControlLayout) -> ControlLayout {
        var copy = layout
        copy.id = UUID().uuidString
        copy.copiedFrom = layout.name
        copy.name = uniqueName("\(layout.name) copy")
        yours.append(copy)
        save()
        return copy
    }

    /// Stores a changed layout of yours (built-in ones can't change).
    public func update(_ layout: ControlLayout) {
        guard let index = yours.firstIndex(where: { $0.id == layout.id }), yours[index] != layout else { return }
        yours[index] = layout
        save()
    }

    public func rename(_ id: String, to name: String) {
        guard var layout = yours.first(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        layout.name = trimmed
        update(layout)
    }

    public func delete(_ id: String) {
        yours.removeAll { $0.id == id }
        save()
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(all.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("akvavit-control-layouts.json")
    }

    /// Writes the file atomically, off the main thread, one write after another.
    private func save() {
        let file = File(haptics: haptics, layouts: yours)
        let url = Self.fileURL
        let previous = saving
        saving = Task.detached(priority: .utility) {
            await previous?.value
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(file) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
