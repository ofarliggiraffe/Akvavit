// SPDX-License-Identifier: GPL-3.0-or-later
//
// Microsoft's 32-bit MFC (mfc140.dll, mfc140u.dll) for 32-bit programs, linked into
// C:\windows\syswow64 at each session start, as Madeira links its 64-bit Visual C++ runtime
// into system32 (WineProcessBridge.m, "Symlinked N MS VC++ Runtime DLLs").
//
// Wine has no MFC, and Steam's Visual C++ installers, which would put it there on Windows,
// hang in Akvavit (Microsoft's installer engine; Madeira met the same with Red Dead
// Redemption 2, GameRecommendations.swift). Age of Empires II HD's launcher imports
// mfc140u.dll and stopped at once with c0000135.
//
// The files are Microsoft's, unmodified, from its official redistributable: the build puts
// them into the bundle's i386-vcruntime (akvavit/scripts/prepare-vcruntime-extra.sh; never
// committed), and Documents/vcruntime-x86 overrides them, as Documents/vcruntime does for
// the 64-bit runtime. Only MFC: Wine's own 32-bit vcruntime140, msvcp140 and the rest stay.
// env.MADEIRA_MFC = 0 leaves MFC out, as for 64-bit.
//
// Hook in Madeira's WineProcessBridge.m, marked "Akvavit:", right after the i386 farm is
// linked into syswow64. AkvavitInstallScripts.recordSupplied uses suppliesX86.

import Foundation

enum AkvavitVCRuntime {
    static let bundleFolder = "i386-vcruntime"
    static let documentsFolder = "vcruntime-x86"

    /// Each DLL's source by lower-cased name: Documents first, then the bundle.
    static func sources(bundle: URL?) -> [String: URL] {
        let fm = FileManager.default
        var folders: [URL] = []
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            folders.append(documents.appendingPathComponent(documentsFolder, isDirectory: true))
        }
        if let bundle { folders.append(bundle.appendingPathComponent(bundleFolder, isDirectory: true)) }
        var result: [String: URL] = [:]
        for folder in folders {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            where name.lowercased().hasSuffix(".dll") && result[name.lowercased()] == nil {
                result[name.lowercased()] = folder.appendingPathComponent(name)
            }
        }
        return result
    }

    /// This app gives 32-bit programs the Visual C++ 14 runtime Steam's installers would:
    /// Wine's own runtime plus Microsoft's MFC.
    static var suppliesX86: Bool {
        !mfcOff && sources(bundle: Bundle.main.resourceURL)["mfc140u.dll"] != nil
    }

    static var mfcOff: Bool { getenv("MADEIRA_MFC").map { $0.pointee == UInt8(ascii: "0") } ?? false }

    /// Links the DLLs into the prefix's syswow64, replacing links from an earlier session.
    static func link(prefix: URL, bundle: URL) {
        let fm = FileManager.default
        let syswow64 = prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        var linked = 0
        for (name, source) in sources(bundle: bundle).sorted(by: { $0.key < $1.key }) {
            let target = syswow64.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            if mfcOff && name.hasPrefix("mfc") {
                fputs("[WineProc] 32-bit \(name) left out (MADEIRA_MFC=0)\n", stderr)
                continue
            }
            if (try? fm.createSymbolicLink(at: target, withDestinationURL: source)) != nil { linked += 1 }
        }
        fputs("[WineProc] Symlinked \(linked) MS VC++ Runtime DLLs (32-bit MFC) into syswow64 (Akvavit)\n", stderr)
    }
}

/// Called by WineProcessBridge.m with the prefix and the bundle paths.
@_cdecl("akvavit_link_vcruntime_x86")
func akvavitLinkVCRuntimeX86(_ prefix: UnsafePointer<CChar>, _ bundle: UnsafePointer<CChar>) {
    AkvavitVCRuntime.link(prefix: URL(fileURLWithPath: String(cString: prefix), isDirectory: true),
                          bundle: URL(fileURLWithPath: String(cString: bundle), isDirectory: true))
}
