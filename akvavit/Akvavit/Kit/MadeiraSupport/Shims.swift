// Akvavit: stand-ins for the few pieces of Madeira's interface code that the
// Madeira engine files compiled into AkvavitKit refer to. Madeira's own
// versions live in its interface files (Library.swift and others), which
// AkvavitKit leaves out.

import Foundation

/// Madeira's ExternalDrives (folders on USB drives as Windows drives). Akvavit
/// has no external drives yet: every library is on drive C.
enum ExternalDrives {
    static var steamLibraries: [String] { [] }
    static func nativeURL(_ relative: String, write: Bool = false) throws -> URL {
        _ = try ExternalStoragePath.components(relative)
        return MadeiraDock.drive.appendingPathComponent(relative)
    }
}

/// Madeira's setup walkthrough, offered from its JIT settings view
/// (JITSetup.swift). Akvavit's interface has its own setup, so Madeira's is
/// never offered.
final class OnboardingModel: ObservableObject {
    static let shared = OnboardingModel()
    var available: Bool { false }
    func rerun() {}
}

enum DeviceLoadDiagnostics {
    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
