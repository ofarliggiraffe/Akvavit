// SPDX-License-Identifier: GPL-3.0-or-later
//
// The control layouts: the built-in ones and the user's own copies, kept in
// one file, and the switch that turns off haptics for every layout. Built-in
// layouts can be changed too (the user, 2026-11-02): a changed one is kept in
// the file over the app's version, keeps its name, and Restore defaults goes
// back to the app's version (also after an update changed the built-in).

import Foundation
import Observation

@MainActor @Observable
public final class ControlLayoutStore {
    public static let shared = ControlLayoutStore()

    /// The built-in layouts, with your changes.
    public var builtIns: [ControlLayout] { BuiltInLayouts.all.map { changedBuiltIns[$0.id] ?? $0 } }
    public private(set) var yours: [ControlLayout] = []
    /// Built-in layouts you changed, by ID.
    private var changedBuiltIns: [String: ControlLayout] = [:]
    /// Off: no haptics from any control.
    public var haptics = true {
        didSet { if haptics != oldValue { save() } }
    }

    @ObservationIgnored private var saving: Task<Void, Never>?

    private struct File: Codable {
        var version = 1
        var haptics = true
        var layouts: [ControlLayout] = []
        /// Built-in layouts as you changed them.
        var builtIns: [ControlLayout] = []

        init(haptics: Bool, layouts: [ControlLayout], builtIns: [ControlLayout]) {
            self.haptics = haptics
            self.layouts = layouts
            self.builtIns = builtIns
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            haptics = c.value(.haptics, or: true)
            layouts = c.value(.layouts, or: [Lenient<ControlLayout>]()).compactMap(\.value)
            builtIns = c.value(.builtIns, or: [Lenient<ControlLayout>]()).compactMap(\.value)
        }
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let file = try? JSONDecoder().decode(File.self, from: data) {
            haptics = file.haptics
            yours = file.layouts.filter { !$0.isBuiltIn }
            let known = Set(BuiltInLayouts.all.map(\.id))
            for layout in file.builtIns where known.contains(layout.id) { changedBuiltIns[layout.id] = layout }
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

    /// Stores a changed layout: one of yours, or a built-in one (which keeps
    /// its name; back as the app has it, it is no longer kept).
    public func update(_ layout: ControlLayout) {
        if let original = BuiltInLayouts.all.first(where: { $0.id == layout.id }) {
            var layout = layout
            layout.name = original.name
            guard layout != (changedBuiltIns[layout.id] ?? original) else { return }
            changedBuiltIns[layout.id] = layout == original ? nil : layout
            LogStore.shared.log("[controls] built-in \(layout.id) " + (layout == original ? "back as shipped" : "changed"))
            save()
            return
        }
        guard let index = yours.firstIndex(where: { $0.id == layout.id }), yours[index] != layout else { return }
        yours[index] = layout
        save()
    }

    /// A built-in layout you changed.
    public func isChanged(_ id: String) -> Bool { changedBuiltIns[id] != nil }

    /// A built-in layout back as the app has it.
    public func restore(_ id: String) {
        guard changedBuiltIns.removeValue(forKey: id) != nil else { return }
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
        let file = File(haptics: haptics, layouts: yours,
                        builtIns: BuiltInLayouts.all.compactMap { changedBuiltIns[$0.id] })
        let url = Self.fileURL
        let previous = saving
        saving = Task.detached(priority: .utility) {
            await previous?.value
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            // A failed save says so: it used to fail without a word, and
            // changes were lost at the next start (2026-11-02).
            do {
                let data = try encoder.encode(file)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                LogStore.shared.log("[controls] layouts saved: yours=\(file.layouts.count) built-in changed=\(file.builtIns.map(\.id))")
            } catch {
                LogStore.shared.log("[controls] layouts NOT saved: \(error)", level: .error)
            }
        }
    }
}
