// SPDX-License-Identifier: GPL-3.0-or-later
//
// Rules for Madeira Dock's one-time installs (DockInstallers.swift), for Steam's shared
// redistributables (AkvavitSteamRedist.swift):
//
// - A "Run Process" entry may name a batch file. Steam's Visual C++ 2015, 2019 and 2022
//   scripts run "Microsoft Visual C++ 20xx x86.cmd", which starts vc_redist with /q and maps
//   3010 to 0. Madeira took only .exe and .msi, so these were left out without a word, and
//   the 2015-2022 runtime (with MFC, which Age of Empires II HD's launcher needs) never
//   installed. The batch already runs each program with `call`, which runs a .cmd and
//   returns its exit code.
// - Exit 1638 (ERROR_PRODUCT_VERSION): a newer version of the same runtime is installed.
//   Steam's 2015 package is older than its 2019 and 2022 ones, which install the same
//   Visual C++ 14 runtime, so after them it ends with 1638 although nothing is missing.
//
// - Steam's Visual C++ 2015, 2017, 2019 and 2022 packages all install the Visual C++ 14
//   runtime, and Microsoft's installer engine hangs in Akvavit (2015 and 2022 did; the 2019
//   one exited at once, since Madeira's prefix template marks 14.42 installed). When the app
//   supplies that runtime to 32-bit programs too (AkvavitVCRuntime: Wine's runtime plus
//   Microsoft's MFC), their runs from Steamworks Shared/_CommonRedist are recorded as done
//   before the plan, as a finished run records them, and never start. Older runtimes
//   (2005-2013) still run.
// - DirectX (CommonRedist\DirectX\<release>) likewise. Its setup can't succeed here: for
//   the 64-bit DLLs it starts Microsoft's infinst.exe, which must load at 0x100000000 and has
//   no relocations, and there iOS keeps the app's own program (c0000018). Wine's builtins
//   in both DLL farms already are what it installs (d3dx9_24-43, d3dx10, d3dx11,
//   d3dcompiler, XInput, XAudio, XACT). The failed run made every game's first start a
//   one-time-installs session, and Madeira had to be restarted after it.
// - .NET Framework (CommonRedist\.NET\<version>) likewise, when Wine Mono is installed (the
//   .NET runtime Wine runs .NET programs with; WineMono.swift). Microsoft's .NET installers
//   don't work under Wine (3.5 Client Profile SP1, which Valheim brought, ended with 1603).
//   Madeira runs every script in Steamworks Shared for every game, so it hit each game's
//   first start.
//
// Hooks in Madeira's DockInstallers.swift, marked "Akvavit:": DockInstallScripts.processes,
// Results.succeeded and DockInstallers.prepare (recordSupplied).

import Foundation

enum AkvavitInstallScripts {
    /// A batch file, run by cmd.exe (`lowercased` is the program path in lower case).
    static func isBatch(_ lowercased: String) -> Bool {
        lowercased.hasSuffix(".cmd") || lowercased.hasSuffix(".bat")
    }

    /// The installer found a newer version of its product already installed.
    static func alreadyNewer(_ status: Int) -> Bool { status == 1638 }

    enum Supplied: String { case visualCpp14 = "Visual C++ 14", directX = "DirectX", dotNet = ".NET Framework (Wine Mono)" }

    /// What a run of Steam's shared redistributables installs, when the app supplies it:
    /// Visual C++ 14 (CommonRedist\vcredist\<year>, 2015 and later), DirectX
    /// (CommonRedist\DirectX\<release>) or .NET Framework (CommonRedist\.NET\<version>).
    /// Runs from a game's own folder are never matched.
    static func supplied(_ process: SteamInstallProcess) -> Supplied? {
        guard process.run.hive == .machine,
              process.executable.lowercased().contains("\\steamworks shared\\_commonredist\\") else { return nil }
        let key = process.run.key.lowercased(), base = "software\\valve\\steam\\apps\\commonredist\\"
        if key.hasPrefix(base + "vcredist\\"), let year = Int(key.dropFirst((base + "vcredist\\").count)), year >= 2015 {
            return .visualCpp14
        }
        if key.hasPrefix(base + ".net\\") || key.hasPrefix(base + "dotnet\\") { return .dotNet }
        return key.hasPrefix(base + "directx\\") ? .directX : nil
    }

    /// The runs among a game's programs that install what `available` the app supplies.
    static func suppliedRuns(_ found: [SteamInstallProcess], available: Set<Supplied>) -> [SteamInstallRun] {
        var runs: [SteamInstallRun] = []
        for process in found {
            guard let what = supplied(process), available.contains(what), !runs.contains(process.run) else { continue }
            runs.append(process.run)
        }
        return runs
    }

    /// What this build supplies: Visual C++ 14 with Microsoft's 32-bit MFC (AkvavitVCRuntime),
    /// DirectX's redistributable DLLs as Wine builtins in the 32-bit farm, and .NET Framework
    /// once Wine Mono is installed.
    @MainActor static var available: Set<Supplied> {
        var result: Set<Supplied> = []
        if AkvavitVCRuntime.suppliesX86 { result.insert(.visualCpp14) }
        if let farm = Bundle.main.resourceURL?.appendingPathComponent("i386-windows/d3dx9_43.dll"),
           FileManager.default.fileExists(atPath: farm.path) { result.insert(.directX) }
        if WineMonoModel.available { result.insert(.dotNet) }
        return result
    }

    /// Records those runs as done, as a finished run records them, before the plan reads the
    /// registry.
    @MainActor static func recordSupplied(_ found: [SteamInstallProcess], prefix: URL, available: Set<Supplied>? = nil) {
        let available = available ?? Self.available
        let runs = suppliedRuns(found, available: available)
        guard !runs.isEmpty else { return }
        do {
            let changed = try SteamInstallScripts.mark(runs, prefix: prefix)
            guard changed > 0 else { return }
            LogStore.shared.log("[akvavit-redist] recorded as done, the app supplies " +
                                available.map(\.rawValue).sorted().joined(separator: " and ") + ": " +
                                runs.map { DockInstallScripts.label($0) }.joined(separator: ", ") + " (values=\(changed))")
        } catch {
            LogStore.shared.log("[akvavit-redist] not recorded: \(error.localizedDescription)", level: .error)
        }
    }
}
