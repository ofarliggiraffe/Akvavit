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
| `App/AkvavitApp.swift` | The app's entry point. |
| `App/RootView.swift`, `App/TabColumn.swift`, `App/Theme.swift`, `App/LibraryView.swift`, `App/GetGamesView.swift`, `App/GameGrid.swift`, `App/CoverView.swift`, `App/GamePopup.swift`, `App/GameInfoFace.swift`, `App/GameSettingsFace.swift`, `App/Play.swift`, `App/SetupView.swift` | The interface, as the user designed it (the mockup canvas): tab column, theme, Library and Get games, the game popup with its flip and settings side, what Play does before a game starts (JIT, Valve's client files), and setup (welcome, JIT, Steam sign-in, done). |
| `App/Test/*` | **Temporary test screens**, only for checking AkvavitKit on the device. The real interface replaces all of them. |
| `Kit/Steam.swift` | Sign-in (on SwiftSteam's sign-in model), the account's games, downloads, uninstall, Valve's client files. **For now it uses Madeira's `MadeiraDock.games` (installed games), `SteamRuntimeInstaller` (Valve's client files), and for uninstall `SteamInstallFiles.delete` and Dock's install ledger.** |
| `Kit/Games.swift` | One game list for the interface: installed games from the install records (offline; through Madeira's `MadeiraDock.games` and `SteamInstallFiles.sizeOnDisk`), the account's games from Steam, a disk cache. |
| `Kit/GameSettings.swift` | Each game's settings (x87, screen size, controls), kept in one file, and the start they make (`LaunchConfig`). |
| `Kit/Setup.swift` | Setup's state (done once, run again) and its JIT chain: pairing, the VPN, the check, each starting the next. |
| `Kit/SteamFacts.swift` | Release years (a product-info request of our own, read with SwiftSteam's `VDFParser`) and the account's playtime (our own `Player.GetOwnedGames` request and reply, written from the public message format with SwiftSteam's protobuf encoder and decoder). |
| `Kit/DownloadActivity.swift` | Downloads that go on in the background: one continued processing task (BackgroundTasks) for the download queue, whose progress iOS shows in a Live Activity. |
| `Kit/Covers.swift` | Covers from Steam's CDN: download, disk cache, downsampled decoding, memory cache. |
| `Kit/Session.swift` | Starting and watching a Windows session: `LaunchConfig` → environment, then the engine's start calls. **For now it uses Madeira's `StikJITHelper` for the JIT pool and the debugger detach.** |
| `Kit/DockStart.swift` | Starting a Steam game through Madeira Dock: the sign-in transfer, the game, the one-time installs, Dock's variables. Calls Dock's interface in `MadeiraDock.swift` and `DockInstallers.swift` (Madeira's, to replace); the steps follow what Dock expects. |
| `Kit/GameOverlay.swift` | A window above the game's picture for in-game interface: it takes every touch (a menu), or only those the interface claims (controls), and can switch between the two while it shows. |
| `Kit/ControlLayouts.swift`, `Kit/BuiltInLayouts.swift`, `Kit/ControlLayoutStore.swift`, `Kit/VirtualKeys.swift` | On-screen control layouts: the model (places measured from the safe area's edges, what each control sends), the four built-in layouts from the design canvas, the user's copies kept in one file, Windows' virtual keys and their names. Written from scratch; nothing of Madeira's controls. |
| `Kit/ControlsRuntime.swift` | Controls in play: which control each finger is on, press timing, Hold and Sticky, what goes to the game (the engine's key and mouse calls). |
| `App/Controls/ControlFace.swift`, `App/Controls/ControlsOverlay.swift` | How controls look (one renderer for the game, the studio and the Controls tab), and the controls over a running game with the test menu above them. |
| `Kit/GameSurface.swift` | The picture's place (the window-level Metal layer, layout) and touch as mouse (off when a control layout says so; a click lets sticky keys go). Follows two findings of Madeira's: the layer must not be in a SwiftUI-hosted view, and presents need the layer's display sync off. |
| `App/AppIcon.icon` (the app icon as an Icon Composer file, which iOS 26 and later uses: background, light and dark layers), `App/Assets.xcassets` (the same icon whole, as the fallback), `scripts/make-app-icon.swift` (draws the images) | The icon the user chose on the design canvas (option C, a controller filled with a wireframe grid). |
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

## Third-party files (not Madeira's)

| File | What it is |
|---|---|
| `App/Fonts/Quicksand-Variable.ttf` | The Quicksand font, unchanged (Google Fonts' `ofl/quicksand/Quicksand[wght].ttf`, renamed). SIL Open Font License 1.1, Reserved Font Name "Quicksand". |
| `App/Fonts/Quicksand-OFL.txt` | Its licence. |

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
