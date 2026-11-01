// SPDX-License-Identifier: GPL-3.0-or-later
//
// Game covers: downloaded once from Steam's CDN into the caches folder, then
// decoded at the size they are shown (ImageIO thumbnails), with the decoded
// images kept in memory while there is room. A few downloads run at a time;
// a cancelled task (a cover scrolled away) stops its download.

import Foundation
import ImageIO
import UIKit

@MainActor
public final class Covers {
    public static let shared = Covers()

    private let memory = NSCache<NSString, UIImage>()
    /// Games none of whose cover URLs worked, this app run.
    private var missing = Set<String>()
    private let downloads = DownloadSlots(count: 4)

    private init() {
        memory.countLimit = 120
    }

    /// Sizes in steps, so slightly different cells share a decode.
    private static func step(_ pixelHeight: CGFloat) -> CGFloat {
        max(100, (pixelHeight / 100).rounded(.up) * 100)
    }

    private static func key(_ game: Game, _ height: CGFloat) -> NSString {
        "\(game.id)@\(Int(height))" as NSString
    }

    /// The largest size each game's cover has been decoded at.
    private var largest: [String: CGFloat] = [:]

    /// The cover if it is decoded already: at that size, else at another size
    /// (until the right one is ready). No waiting, so no placeholder flashes.
    public func cachedImage(for game: Game, pixelHeight: CGFloat) -> UIImage? {
        if let image = memory.object(forKey: Self.key(game, Self.step(pixelHeight))) { return image }
        guard let height = largest[game.id] else { return nil }
        return memory.object(forKey: Self.key(game, height))
    }

    /// The game's cover, decoded to at most `pixelHeight` pixels high, or nil
    /// if there is none (or the task was cancelled).
    public func image(for game: Game, pixelHeight: CGFloat) async -> UIImage? {
        let height = Self.step(pixelHeight)
        let key = Self.key(game, height)
        if let image = memory.object(forKey: key) { return image }
        guard !missing.contains(game.id) else { return nil }

        let file = Self.fileURL(for: game)
        if !FileManager.default.fileExists(atPath: file.path) {
            guard await download(game, to: file) else { return nil }
        }
        guard !Task.isCancelled, let image = await Self.decode(file, maxPixels: height) else { return nil }
        memory.setObject(image, forKey: key)
        largest[game.id] = max(largest[game.id] ?? 0, height)
        return image
    }

    private func download(_ game: Game, to file: URL) async -> Bool {
        await downloads.wait()
        defer { Task { await downloads.signal() } }
        for url in game.coverURLs {
            if Task.isCancelled { return false }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      (response.mimeType ?? "").hasPrefix("image/"), !data.isEmpty else { continue }
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                return true
            } catch {
                // Offline or cancelled: try again next time.
                return false
            }
        }
        missing.insert(game.id)
        return false
    }

    private static func fileURL(for game: Game) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("\(game.source.rawValue)-\(game.appID).jpg")
    }

    private nonisolated static func decode(_ file: URL, maxPixels: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }
}

/// A counting semaphore for async code.
private actor DownloadSlots {
    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { free = count }

    func wait() async {
        if free > 0 {
            free -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func signal() {
        if waiting.isEmpty {
            free += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
