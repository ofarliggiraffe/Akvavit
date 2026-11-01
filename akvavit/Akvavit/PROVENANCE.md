# What is ours and what is Madeira's

Akvavit's own app (this folder) is built from three kinds of code. Every file the
app compiles or bundles falls under exactly one heading below; `project.yml`
groups them the same way. Keep this list exact: a file moves from "Madeira's
Swift, to replace" to "Ours" only when our own version has replaced it.

Nothing of Madeira's is copied into this folder. Madeira's files are compiled
from where they are in the repository (`app/`), unchanged.

## Ours

Written for Akvavit. Where a file stands in for something of Madeira's, it says so.

| File | What it is |
|---|---|
| `project.yml` | The project. Its project-level build settings are the values Madeira's project sets, so Madeira's files compile the same way. |
| `App/AkvavitApp.swift`, `App/JITSetupView.swift`, `App/AboutView.swift`, `App/GameScreen.swift` | The interface. |
| `Kit/Session.swift` | Starting and watching a Windows session: `LaunchConfig` → environment, then the engine's start calls. **For now it uses Madeira's `StikJITHelper` for the JIT pool and the debugger detach.** |
| `Kit/GameSurface.swift` | The picture's place (the window-level Metal layer, layout) and touch as mouse. Follows two findings of Madeira's: the layer must not be in a SwiftUI-hosted view, and presents need the layer's display sync off. |
| `App/Info.plist`, `App/Akvavit.entitlements` | The app's keys and capabilities. |
| `Kit/AkvavitKit.swift` | `AkvavitEngine.start()`. |
| `Kit/JIT.swift` | AkvavitKit's JIT model. **For now it drives Madeira's JIT code** (`JITCoordinator`, `OnDevicePairing`, `StikJITHelper`); its public API is ours and stays when that code is replaced. |
| `Kit/Engine/module.modulemap`, `Kit/Engine/MadeiraEngine.h` | Make Madeira's C interface (its bridging header) a module. |
| `Kit/MadeiraSupport/Shims.swift` | Stand-ins for three things of Madeira's interface code that its compiled-in files refer to (`ExternalDrives`, `OnboardingModel`, `DeviceLoadDiagnostics`). `DeviceLoadDiagnostics.thermalName` names the four thermal states, as Madeira's does. These go when the files that need them are replaced. |
| `Kit/MadeiraSupport/EngineCallbacks.swift` | `winios_mouse_routing_enabled`, which Madeira's native code calls; the same rule as Madeira's (on unless `env.MADEIRA_MOUSE_ROUTING = 0`). |
| `scripts/embed-stikjit.sh`, `scripts/sign-bundled-dylibs.sh` | Build phases. They do the same jobs as the inline scripts in Madeira's project (StikJIT into Frameworks; the licence check and dylib signing). |
| `../App/AkvavitTunnel.swift` | Our JIT VPN (also in Madeira's app). |
| `../App/AkvavitSteamPoll.swift`, `AkvavitSteamRedist.swift`, `AkvavitInstallScripts.swift`, `AkvavitSessionLogs.swift`, `AkvavitVCRuntime.swift` | Our earlier additions to Madeira's app, shared. They are written against Madeira's types (`MadeiraDock`, `LogStore`…) and change with them. |
| `../Tunnel/*` | The tunnel extension (also in Madeira's app). |

## Madeira's components (kept; may be replaced later)

Used as they are, like Wine or FEX. Each is a unit with an interface we call.

| Component | Files |
|---|---|
| Native engine | The static libraries from `akvavit/scripts/build-native.sh`: Wine's unix side (`libntdll_unix`, `libwin32u_unix`, `libwineserver`), DXMT, FEX, FFmpeg, GnuTLS, `libmadeira_rppairing`. |
| Native glue | `app/Madeira/`: `JITAllocator.c`, `FEXBridge.mm`, `WineServerBridge.m`, `WineProcessBridge.m`, `wine_stubs.c`, `PrefixExtractor.c`, `IOSDisplayShim.m`, `PadOutput.m`, `Winios/` (`Winios.m`, `WiniosGL.m`, `WiniosCursor.c`, `WiniosGamepad.c`). Its interface: `Madeira-Bridging-Header.h` and the headers it includes. |
| Bundled files | `app/Madeira/`: the DLL farms (`aarch64-windows`, `arm64ec-windows`, `i386-windows`), `nls`, `compat`, `gl`, `vulkan`, `d3d12`, `x86_64-opengl`, `x86_64-vcruntime`, `i386-vcruntime`, `legal`, `licenses`, `prefix-template.tar.gz`, `cacert.pem`, `madeira-jit.js` (the debugger script). Wine Mono through `build/wine-mono/bundle.sh`. |
| JIT helper extension | `app/MadeiraJITHelper/` (with its message format, `app/Madeira/JITBuiltInMessages.swift`), StikJIT (`akvavit/vendor/StikJIT`, built from source). |
| SwiftSteam | `app/Madeira/SwiftSteam/` without `SteamSignInView.swift` (interface). |
| Madeira Dock | `madeira-dock/` (`dockhost.exe`, in the DLL farm). |

## Madeira's Swift, compiled in for now (to replace)

Madeira's own app logic, compiled so the first game runs sooner. Each is to be
replaced by our own code behind AkvavitKit's API. Unchanged, except for hooks
marked `Akvavit:` that Madeira's app has too:

- `JITPairing.swift`: the pairing name is the app's display name (Madeira's app:
  "Madeira", ours: "Akvavit").

| File | What it does for us now | Replaced by |
|---|---|---|
| `StikJITHelper.swift`, `JITSetup.swift` (`JITCoordinator`), `JITBuiltInHost.swift`, `JITNetwork.swift`, `JITPairing.swift`, `EntitlementChecker.swift`, `JITPoolMeter.swift` | Pairing, enabling JIT, the JIT pool request, signing checks | our JIT flow (`Kit/JIT.swift` behind the same API) |
| `MadeiraDock.swift`, `DockInstallers.swift`, `DockReset.swift` | Dock starts and one-time installs | our Dock launcher |
| `LogStore.swift`, `LogTail.swift`, `LogSummary.swift`, `LogPattern.swift` | The log | our logging |
| `MadeiraConfig.swift` | `madeira.cfg` | our settings |
| `SteamKeyValues.swift`, `SteamInstall.swift`, `SteamRuntime.swift`, `ExternalStorage.swift` | Steam file formats and paths, Valve's client files (SwiftSteam needs the first two) | our Steam support |
| `WineMono.swift` | Wine Mono's presence and download | our own |
