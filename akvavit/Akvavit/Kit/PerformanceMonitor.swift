// SPDX-License-Identifier: GPL-3.0-or-later
//
// How a running game is doing, once a second, for the performance bar:
//
//   frames per second  the engine's count of frames shown (madeira_frame_count);
//   CPU                the app's processor time (getrusage, every thread: the
//                      game, Windows, the emulation and the app around them)
//                      as a share of all cores;
//   GPU                the time Metal spent on the game's command buffers, as
//                      a share of the wall time (DXMT's meter,
//                      madeira_gpu_meter_*: Direct3D 9-11 games). nil for games
//                      drawn another way (Direct3D 8, DirectDraw, OpenGL go
//                      through Zink and MoltenVK, which the meter doesn't see).
//                      iOS's own count for the app's coalition stayed empty on
//                      the Duo (2026-11-02).
//
// A [perf] line goes to the log every 10 s while it runs.

import Darwin
import Foundation
import Observation

public struct PerformanceSample: Equatable, Sendable {
    public var framesPerSecond: Double
    /// 0...100, of all cores.
    public var cpu: Double
    /// 0...100; nil when unknown.
    public var gpu: Double?
}

@MainActor @Observable
public final class PerformanceMonitor {
    public static let shared = PerformanceMonitor()

    /// The last second's numbers; nil until a second has passed.
    public private(set) var sample: PerformanceSample?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var viewers = 0

    private init() {}

    /// Starts sampling; each `start` is paired with a `stop`.
    public func start() {
        viewers += 1
        guard task == nil else { return }
        madeira_gpu_meter_enable(1)
        task = Task { [weak self] in
            var previous = Reading.now()
            var logged = previous.wall
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let reading = Reading.now()
                let sample = reading.sample(since: previous)
                previous = reading
                self?.sample = sample
                if reading.wall - logged >= 10 {
                    logged = reading.wall
                    LogStore.shared.log(String(format: "[perf] fps %.1f cpu %.0f%% gpu %@", sample.framesPerSecond,
                                               sample.cpu, sample.gpu.map { String(format: "%.0f%%", $0) } ?? "unknown"))
                }
            }
        }
    }

    public func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        task?.cancel()
        task = nil
        sample = nil
        madeira_gpu_meter_enable(0)
    }

    private struct Reading {
        var wall: Double
        var frames: UInt64
        var cpu: Double
        /// Busy seconds and command buffers counted so far.
        var gpu: Double
        var buffers: UInt64

        static func now() -> Reading {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1e6 }
            return Reading(wall: ProcessInfo.processInfo.systemUptime, frames: madeira_frame_count(),
                           cpu: seconds(usage.ru_utime) + seconds(usage.ru_stime),
                           gpu: madeira_gpu_meter_busy_seconds(), buffers: madeira_gpu_meter_cmdbufs())
        }

        func sample(since earlier: Reading) -> PerformanceSample {
            let elapsed = max(wall - earlier.wall, 0.001)
            let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
            func percent(_ value: Double) -> Double { min(max(value * 100, 0), 100) }
            // No command buffers counted: the game draws another way.
            let gpu: Double? = buffers > earlier.buffers ? percent((self.gpu - earlier.gpu) / elapsed) : nil
            return PerformanceSample(framesPerSecond: Double(frames &- earlier.frames) / elapsed,
                                     cpu: percent((cpu - earlier.cpu) / elapsed / cores), gpu: gpu)
        }
    }
}
