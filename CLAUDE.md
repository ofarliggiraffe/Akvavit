# Akvavit

A public fork of [Madeira](https://github.com/willfaust/Madeira), which runs
Windows games on iPhone with FEX-Emu, Wine 11.4 and DXMT, with our own changes
on top. The first game is **Railroad Tycoon 3**, and the device is an **iPhone
Duo**. Personal details (device, team, accounts) are in `CLAUDE.local.md`,
which is git-ignored.

## The repository is public: nothing personal goes in it

- No names, usernames, email addresses, team IDs, bundle-ID prefixes, device
  UDIDs or home-directory paths in any tracked file or commit message, in
  this repository or in `wine/` (Akvavit's Wine fork, public too).
- Personal values live in `local.config` (git-ignored). Scripts read them from
  there; signing gets them through `app/Signing.local.xcconfig` (git-ignored,
  written by `akvavit/scripts/setup.sh`).
- `akvavit/scripts/check-personal.sh` runs as the pre-commit,
  pre-merge-commit, commit-msg and pre-push hooks (`core.hooksPath` =
  `akvavit/githooks`), and as `--everything` in CI. Never bypass it.
  `.claude/hooks/guard-git.sh` refuses `--no-verify`, `git commit -n` and
  `core.hooksPath` changes, and scans `gh` PR and issue text. If something is
  flagged, remove it.
- The check covers only what we add on top of Madeira: commits not in
  `refs/remotes/upstream/*`, files only we have (whole), and in Madeira's
  files only findings its version (at the merge base) lacks. So the `upstream`
  remote must exist (`setup.sh` adds it, with Madeira's tags under
  `upstream/tags/`). It also refuses staged changes to Madeira's binaries,
  which local builds rewrite (`AKVAVIT_ALLOW_BINARY=1` for a deliberate one).
- The hooks don't run in submodules. Before pushing `wine/`, run its new
  commits and diff through `check-personal.sh --text`.
- The guard reads command text, so a command that merely mentions a refused
  flag is refused too (write such text with the file tools). A command that
  mentions a personal value (e.g. the scratchpad path, which holds the
  username) right after `gh ` is refused, so put such tests in a script file.
  It also refuses commands that look like git commits, merges or pushes while
  the hooks aren't installed.
- macOS's `/bin/bash` 3.2 has crashed in `fork()` (exit 137) when scripts held
  whole files in variables. Keep large text in files, not in variables or
  here-strings.
- Commits use the repository-local GitHub noreply identity and are signed off
  (`git commit -s`, DCO, as Madeira asks), so any of them can go upstream.
  `wine/` has the same identity set.
- Commit and push only when the user asks.

## Layout

- The repository root is Madeira's tree. Branch `akvavit` (the default) is
  Madeira's `main` plus our commits. Remotes: `origin` = our fork,
  `upstream` = `willfaust/madeira`. Never push upstream's branches to
  `origin` (Madeira's CI workflow is disabled in the fork).
- Keep changes to Madeira's files small, so merges stay easy. Put the logic in
  new files under `akvavit/`, and only hook them in from Madeira's files, with
  an `Akvavit:` comment at each hook.
- Keep Madeira's names (project, targets, scheme `Madeira`, `Madeira.app`);
  only the display name is Akvavit. Renaming them would conflict on every
  merge of `project.pbxproj`.
- `akvavit/App` (app files), `akvavit/Tunnel` (the tunnel extension, target
  `AkvavitTunnel`). New files are added in Xcode (the project file is ours to
  edit now). Project paths to them start with `../akvavit/`.
- `app/Signing.xcconfig`: the project's base configuration (team and bundle
  ID placeholders, then `#include? "Signing.local.xcconfig"`). The project
  file must not set `DEVELOPMENT_TEAM` or `MADEIRA_BUNDLE_IDENTIFIER` itself.
  Xcode writes `DEVELOPMENT_TEAM` into a target when a team is picked in
  Signing & Capabilities, so don't pick one there, and remove it if it appears.
- `akvavit/scripts/setup.sh`: hooks, the `upstream` remote, submodules,
  `Signing.local.xcconfig`, privacy check. Safe to re-run.
- `akvavit/scripts/build-native.sh`: Madeira's `tools/build-ipa.sh` minus
  packaging, with our build fixes, then `build-stikjit.sh`. Logs go to
  `.build/logs/`.
- Builds dirty the tree: they rebuild tracked binaries (the DLL farms,
  libraries) and Xcode re-sorts `Info.plist`. Never commit those; stage only
  the files you changed. The pre-commit hook refuses changed Madeira binaries.
- `akvavit/vendor/StikJIT` (tag 1.9.0) and `akvavit/vendor/idevice` (tag
  v0.1.68): submodules that `akvavit/scripts/build-stikjit.sh` builds into
  `app/Frameworks/StikJIT.xcframework` (git-ignored, a build output). It
  builds from copies in `.build/stikjit` and checks the idevice header and
  StikJIT's public interface against Madeira's prebuilt originals (read from
  the merge base with `upstream/main`). It is the one script that calls
  `xcodebuild` (a library build that has to work for every user). When
  changing a submodule pin, stage it (`git add akvavit/vendor/…`); otherwise
  `git submodule update` goes back to the old commit.
- `wine`: points to `ofarliggiraffe/wine`, branch `akvavit` (Madeira's pinned
  Wine from `willfaust/wine` `madeira-lgpl`, plus our commits). In `wine/`,
  `origin` = our fork, `upstream` = `willfaust/wine`. FEX, dxmt and
  madeira-dock stay on Madeira's forks. Never change FEX (see Decisions).
- `MADEIRA.md` is Madeira's README (renamed; `README.md` is ours).

## Updating Madeira

Only deliberately, then a native rebuild and the device tests (JIT, RT3
through Dock at 60 FPS, RT2, Portal).

1. `git fetch upstream && git merge upstream/main` on `akvavit`; resolve
   conflicts. `README.md` conflicts whenever Madeira changes its README: keep
   ours (`git checkout --ours README.md`), and refresh `MADEIRA.md` with
   `git show upstream/main:README.md > MADEIRA.md`.
2. If upstream moved the `wine` pointer: in `wine/`, `git fetch upstream &&
   git merge upstream/madeira-lgpl` on `akvavit`. If `unix_thunks.c`
   conflicts, take upstream's and run `akvavit/scripts/regen-opengl-thunks.sh`.
   Check the new commits, push `wine`'s `akvavit` (on the user's OK), and
   commit the pointer.
3. The same for the StikJIT pins if needed.

## Decisions

- **Keep Madeira's iOS app** and change it minimally. Rewriting it would bring
  back input and Wine-startup bugs it has already fixed.
- **FEX stays untouched.** FEX-Emu doesn't accept AI-generated code; don't
  write FEX code without asking the user. A FEX change would live only in our
  own fork of it, carried across every update. The user would consider it if
  more games need what only FEX can provide (first case: hardware breakpoints
  for AoE II DE, see below); raise it then.
- **JIT, with nothing prebuilt from outside:**
  - our own loopback packet-tunnel extension inside the app, replacing
    LocalDevVPN. The app starts it when enabling JIT and stops it once the
    debugger has detached. It must work offline (airplane).
  - StikJIT (MPL-2.0) built from source instead of the bundled prebuilt
    xcframework.
- **Extra Windows DLLs** (e.g. d3d8to9, cnc-ddraw): only open-source ones, built
  from source, bundled and applied per game by the app. No manual steps after
  install. dgVoodoo2 is out, because it is closed source.
- **Full Duo support:** resize on fold and unfold, and move between displays.
- **Steam sign-in** is acceptable after reviewing Madeira's Steam code.
  Reviewed 2026-10-30 (commit c2c1b03), no concerns:
  - the password is RSA-encrypted with Steam's key and sent only to
    `api.steampowered.com` over normal TLS, never stored or logged;
  - the tokens are in the Keychain (`WhenUnlockedThisDeviceOnly`);
  - only Valve's servers are contacted, and no TLS checks are overridden;
  - logs carry no credentials or account names;
  - Valve's client files are SHA-256 pinned;
  - Madeira Dock passes the token to Steam in Wine through a protected,
    one-use file (readable by Windows programs in that session, as on a PC).
  `akvavit/App/AkvavitSteamPoll.swift` keeps the sign-in polling alive while the app is in the
  background (approving in the Steam app used to end it).
- **Credit belongs to Madeira.** Wherever Akvavit has text of its own (setup
  screens, README, about pages), say plainly that this is Madeira by its
  authors, and that Akvavit only packages it for easy installation. Claim
  almost nothing for ourselves.
- **Never use Madeira's Settings → Signing.** It sends the Apple ID through
  third-party anisette servers. Xcode signing with a paid account lasts a
  year.

## Madeira facts verified from its source (commit c2c1b03)

- A SwiftUI app with a generated scene manifest, so the iOS 27 UIScene
  requirement is met. Deployment target 17.0, helper extension 26.0.
- **D3D8 and DirectDraw** are Wine's own modules, drawn through wined3d →
  OpenGL → Zink → MoltenVK → Metal. Both DLL farms include them, but this path
  is unverified on a device. D3D9, 10 and 11 go through DXMT.
- **32-bit (WoW64) guest memory lives in a window at `0x7100000000`.** Unix-side
  code must convert 32-bit guest pointers with `ios_wow_host_ptr()`
  (`wine/include/wine/unixlib.h`). Madeira did that for the hand-written
  unixlibs, but not for opengl32's generated thunks, so 32-bit OpenGL (and with
  it D3D8 through wined3d) crashed in `wow64_thread_attach`. Our Wine fixes
  opengl32 in three commits:
  - the generator `make_opengl`;
  - its regenerated output `unix_thunks.c`, recreated with
    `akvavit/scripts/regen-opengl-thunks.sh`;
  - the hand-written spots (`unix_private.h`, `unix_wgl.c`).

  The client handles `HGLRC`, `HPBUFFERARB` and `GLsync` are pointers to
  records in the program's memory (the Unix side writes into them), and
  `LPCSTR` is a string, so the generator translates those too; only `HDC`
  and other real handles stay as they are.

  Verified 2026-10-30: RT3 (Steam, through Madeira Dock) runs a campaign at
  60 FPS (with the 16 KB image fix below and reduced-precision x87). Texture glitches
  remain, not investigated yet.
  winevulkan's 32-bit thunks have the same problem (Madeira binds them to
  64-bit callers only).
- **32-bit images and 16 KB pages:** Madeira keeps a 32-bit program's image
  as plain writable memory (`ios_guest_image_is_host_data`, `virtual_ios.c`).
  It looked the image up with the 16 KB-rounded range, which reaches past an
  image whose size isn't a multiple of 16 KB. Then the whole image went into
  the JIT pool, and every store to it was emulated in the fault handler
  (RT3: 40,000-80,000 a second, 1-2 FPS). Our change accepts a range
  ending in the image's last host page. Signs in a game's log: `[jit-pool]
  exec page ... is OUTSIDE nearest image` and `[fault-class] ... emulated
  stores so far`.
- **Colour depths:** Madeira's virtual display (`build/win32u-unix/sysparams_ios.c`)
  listed every mode at 32 bits only; upstream Wine lists 8, 16 and 32. Old
  DirectDraw games then found no usable mode (Railroad Tycoon II: "Unable to
  set up video mode"). We list all three, accepts them in a mode
  change and reports the set depth as the current mode, which wined3d reads to
  build its screen. Verified 2026-10-30: RT2 starts.
- **x87 precision:** the game page's "Reduced-precision x87" toggle is off by
  default, and the app exports `FEX_X87REDUCEDPRECISION=0` for every launch,
  overriding the 32-bit module's own default of 1. Then all x87 math runs
  through FEX's 80-bit software helpers. Wine's 32-bit DLLs (d3d8, wined3d)
  use x87, so Direct3D 8 games are slow. RT3: 7 FPS with it off, 60 FPS with
  it on. Direct3D 8 switches the FPU to single precision anyway, unless the
  game asks otherwise.
- **Profiling a slow game:** in the game's session log, `[xp-t]` gives CPU
  per thread (`m…` is the Mach fault handler), `[rip-profile]` the guest
  addresses (synchronised only at calls out of translated code), and
  `[cpu-split]` the hot host code. FEX's `AC [iOS-xins]` lines list each
  32-bit DLL's code section, and the unstripped i386 builds are in
  `wine/build-i386/dlls/<name>/i386-windows/`
  (symbolise with `toolchains/llvm-mingw-*/bin/llvm-symbolizer`).
- `akvavit/scripts/rebuild-wine-unix.sh` rebuilds just Wine's unix side
  (`libntdll_unix.a`, opengl32 included, and `libwin32u_unix.a`) in about
  40 s after a full native build. Then build the app in Xcode.
- Symbolicate a crash PC from Madeira's log: load address = the logged
  `unix_call_dispatcher` value minus the offset of
  `___wine_unix_call_dispatcher` in `nm Madeira.debug.dylib`. Then
  `atos -arch arm64 -o Madeira.debug.dylib -l <load address> <pc>`, with the
  exact binary that was installed.
- **Madeira issue #423 (every 64-bit program crashed at start) has a known
  cause:**
  - Madeira's `build/wine-pe/build-modules.sh` turns delay imports into plain
    imports (lld's ARM64EC delay-load stub breaks in Madeira's JIT pool);
  - for the C runtimes (ucrtbase, msvcrt, msvcr*, crtdll) that makes
    `advapi32`/`user32` load-time dependencies, so a cycle lets DLLs like
    msacm32 run `DllMain` before ucrtbase is initialised;
  - the crash: a null `MSVCRT_locale` in `msvcrt_get_thread_data`, while
    xtajit64 attaches its dependencies.

  Madeira's committed DLLs are fine; only a local native build produces it.
  We keep the C runtimes' delay imports (`build-modules.sh`). Verified 2026-10-30:
  the AoE II DE installer, Dock's host and Valve's client run.
- **Find a loader-order problem** with temporary `ERR(...)` lines in
  `wine/dlls/ntdll/loader.c`, then rebuild the PE ntdll with
  `bash build/wine-pe/build-ntdll.sh` (5 s). `WINEDEBUG` from
  `madeira.cfg` doesn't reach Windows child processes (Dock, installers).
- **Translate a crash in the JIT pool:** `[jit-pool] image <base>+<size> (dll)
  → pool <addr>` lines map pool addresses back to DLLs; the copy keeps the
  image layout. Unstripped PE builds for symbols are in
  `wine/build-arm64ec/dlls/<name>/arm64ec-windows/`.
- **Age of Empires II DE** (64-bit, Steam 813780) is **parked** (2026-10-31): its
  Arxan protection needs x86 hardware breakpoints, which FEX does not emulate.
  - Since Steam's redistributables are installed, Steam starts it; it then
    dies with "Unhandled illegal instruction" (c000001d) at `0x142b9c21c`,
    whose first bytes are `37 9a a6 3f 48` (Steam ships them so).
  - 6,407 of the executable's 169,486 functions (`.pdata`) start with an
    opcode invalid in 64-bit mode: Arxan's encrypted function heads. The file
    names Arxan ("TAMPER", "ARXAN" among its analytics events). The crash is the
    first one the game reaches: the C++ initializer right after the CRT's
    first one calls it.
  - Ruled out: a stale JIT-pool copy (the PE mapping holds the same bytes,
    `[rsp-trunc] x86 @rip` vs `[guest-code]`), base relocations (none in
    `.text`), the dynamic value relocation table (none), the entry point and
    TLS callbacks (standard MSVC), CEG (no `CheckGuid`).
  - The game registers a vectored handler (`0x142bfa4d8` → `0x142c07024`,
    first in line) just before the crash, right after allocating 16 MB RWX.
    Wine calls it for the c000001d and it declines (0). Disassembled, it acts
    only on STATUS_BREAKPOINT and STATUS_SINGLE_STEP (the exception code is
    compared after an XOR with `0x8bc6ab9ad2173b9` and doubling), and reads
    the context's Dr0-Dr2 and Dr7 (offsets 0x48-0x70). So on Windows a
    hardware execute breakpoint on each encrypted head raises a single step
    first, and the handler decrypts the head.
  - In our session Dr0-Dr7 are all zero at the crash and no debug exception
    comes before it. The game imports neither Get- nor SetThreadContext (it
    has `GetProcAddress`, `RaiseException`, and "Unable to get ntdll file
    version/handle" strings, so it may look up calls or make its own system
    calls with numbers read from ntdll on disk). Not measured: whether it
    arms the breakpoints through `NtSetContextThread`/`NtContinue` at all.
  - A fix needs execute breakpoints: properly in FEX (our rule: no FEX
    changes without asking; it could be a feature request to FEX), or a narrow
    Wine-side workaround (record the Dr values a context call sets; turn a
    fault at an armed address into STATUS_SINGLE_STEP with Dr6), which only
    works if the arming reaches Wine. Arxan may then fail further checks, and
    DE is heavy for the device anyway. Worth it only if more games need it.
  - Other Arxan titles are not necessarily affected (Madeira has recommended
    settings for Red Dead Redemption 2); protections that only check that the
    debug registers are zero are fine.
  - Method, for a similar case: temporary `ERR` lines in
    `wine/dlls/ntdll/exception.c` (`RtlAddVectoredExceptionHandler`,
    `call_vectored_handlers` with the context's Dr registers), then
    `build/wine-pe/build-ntdll.sh` (5 s) and the Xcode build. Then
    disassemble the handler with `llvm-objdump` from `toolchains/llvm-mingw-*`.
- **Portal** (Steam, 32-bit, Direct3D 9) runs well through Madeira Dock
  (2026-10-30). Controls: touch as mouse for looking, plus a custom touch
  layout with keys (WASD stick, Space, Ctrl, E) and mouse buttons.
  Madeira's on-screen Xbox pad doesn't reach it, not understood yet:
  - Portal's console shows its controller config loaded (`-condebug
    +joystick 1 +exec 360controller` writes `portal/console.log`);
  - the touch pad's input arrives in Madeira;
  - but Portal's process falls back to Wine's HID controller search
    (`wine_xinput_hid_update` thread) and never logs the XInput calls that
    would find the pad, even with `MADEIRA_PAD_EARLY_SLOT=1` (player 1
    connected before the game starts).

  Next step: temporary logging of every XInput call in the 32-bit xinput.
  A game's Controller choice "XInput and DirectInput" doesn't work through
  Dock: it's exported at Play, but Windows programs inherit their environment
  from Steam, which started earlier. DirectInput reads it from there.
- **Steam's shared redistributables** (Age of Empires II HD and DE):
  - Games can take depots from "Steamworks Common Redistributables" (228980:
    Visual C++ and DirectX installers, `depotfromapp` + `sharedinstall`).
    Madeira's downloader skipped them, so 228980 had no record and Valve's
    client refused the launch (error 17: "Steam is installing content this
    game needs…" for ever). `AkvavitSteamRedist.swift` downloads them before
    a game's download or Repair, as 228980's own install in
    `common/Steamworks Shared`, and the game's record lists them as
    `SharedDepots`.
  - Madeira Dock's one-time installs then run their scripts. Madeira took
    only `.exe`/`.msi`; Steam's Visual C++ 2015-2022 scripts run `.cmd`
    wrappers (`AkvavitInstallScripts.swift`; exit 1638, "newer installed",
    counts as done).
  - Microsoft's Visual C++ 14 installer engine hangs in Akvavit (2015 and
    2022 did; Madeira met it with Red Dead Redemption 2), and DirectX setup
    can't work (its 64-bit `infinst.exe` must load at 0x100000000, where iOS
    keeps the app; c0000018). So Steam's Visual C++ 2015+ and DirectX runs
    are recorded as done when the build supplies them (`[akvavit-redist]`).
    2012 and 2013 still run, and install fine.
  - Visual C++ 14 for 32-bit programs: Wine's own runtime plus Microsoft's
    32-bit MFC, which AoE II HD's launcher imports. Madeira supplies only the
    64-bit runtime, and its build step left out MFC.
    `akvavit/scripts/prepare-vcruntime-extra.sh` (run by `build-native.sh`)
    extracts `mfc140.dll`/`mfc140u.dll` from Microsoft's redistributables,
    32-bit into `app/Madeira/i386-vcruntime` and 64-bit beside Madeira's
    (both git-ignored, never committed). `AkvavitVCRuntime.swift` links the
    32-bit ones into `syswow64` at each session (`Documents/vcruntime-x86`
    overrides; `env.MADEIRA_MFC = 0` leaves them out).
  - Verified 2026-10-31: AoE II HD (Steam, 32-bit, Direct3D 9) starts and
    plays through Dock.
- **The Steam version of Railroad Tycoon 3** (app 7610) is packed with Steam's
  copy protection: without a running Steam client it stops with "Failed to
  find Steam". So it needs Madeira Dock (works), or a DRM-free copy.
- 32-bit games run through WoW64. They need the i386 DLL farm (built locally
  by `build-ipa.sh`) and the Increased Memory Limit and Extended Virtual
  Addressing capabilities on an explicit App ID. A wildcard profile can't
  reserve the guest memory window.
- Build **Debug**. Madeira says Release builds have crashed the guest.
- Madeira ships no scheme files. Xcode only auto-creates
  `MadeiraJITHelper`, so we commit a shared `Madeira` scheme.
- `GuestDisplay.screen` reads `UIScreen.main` once and caches it, which is
  wrong on the Duo (see below).
- JIT: on TXM devices, the debugger must prepare each RX region through a
  `brk #0xf00d` protocol (`app/Madeira/madeira-jit.js`,
  `app/Madeira/JITAllocator.c`). Madeira prepares the pool, then detaches
  before Wine starts. The built-in path reaches lockdownd through a loopback
  VPN at `10.7.0.1`. That works on Wi-Fi or with no network, but not over
  cellular data. LocalDevVPN's tunnel is about 90 lines
  (`NEPacketTunnelProvider` that swaps source and destination IPv4 addresses,
  routing only the peer address).
- Akvavit's own tunnel (`akvavit/Tunnel`) replaces LocalDevVPN. Verified on
  the Duo (2026-10-30): on Wi-Fi it starts in under 0.2 s and JIT comes on
  about 1.5 s after the tap. On cellular data the tunnel connects but the
  iPhone refuses the connection ("Connection refused"). With no network at all
  iOS won't start the tunnel, but a tunnel started earlier keeps working in
  airplane mode with Wi-Fi off. Disconnecting Wi-Fi through Control Center
  doesn't help. A tunnel started over cellular data also works once airplane
  mode is on. So the rule is: no cellular data in use at the moment JIT
  starts. Hence "Keep the JIT VPN on" (default on, with connect-on-demand):
  JIT works on Wi-Fi, or offline with airplane mode on for a moment.
- Mounting the Developer Disk Image most likely needs Apple's servers once
  after each reboot (unverified).
- Touch input: in Touch pointer mode, a one-finger drag past 10 pt (or a
  0.25 s hold) is a left-button drag from the original point, so RTS box
  selection works. A two- or three-finger tap is a right or middle click, and
  a two-finger drag is the wheel (`ContentView.swift`, `touchMode*`).
- **Game type and per-game controls** (`akvavit/App/AkvavitGameControls.swift`):
  - Each library game has a type: User (default, `gameType` nil), Strategy
    or FPS. Each type has defaults: pointer mode, sensitivities, and an
    on-screen layout (FPS: the built-in "FPS keyboard & mouse",
    `builtin.akvavit.fps`).
  - User's defaults are the global `InputSettings` (`madeira-input.json`,
    Settings › Pointer) and the shared layout.
  - A game stores only pointer values that differ from its type's defaults
    (`pointerMode`, `sensAbs`, `sensRel`). Choosing a type resets the game's
    pointer and layout.
  - During a library session `InputSettings` holds the game's values and
    doesn't write its file (`holdsInputFile`). `finish()` brings the global
    values back.
  - Madeira's touch layout was already per game (`LibraryEntry.controls`).
    Games also store their layout only when it differs from the type's.
  - **Settings › Controls** (`AkvavitControlsSettings.swift`, in place of
    Settings › Pointer):
    - Layouts: Madeira's named layouts (`ControlPresetsModel`; its
      `change(_:)` is our hook for saving). New, edit, rename (delete + save
      under the same id), duplicate, delete.
    - Built-in layouts can be edited too. Their edits are kept in
      `Documents/akvavit-builtin-layouts.json` (`AkvavitBuiltInLayouts`) and
      laid over `ControlPresetStore.builtIns`, which is computed now. Reset
      removes them.
    - User, Strategy, FPS: pointer settings, which layout, whether the
      controls show (`Documents/akvavit-control-defaults.json`).
  - **The editor outside a game** (`AkvavitLayoutEditor.swift`) is Madeira's
    in-game editor on the shared working copy, set aside and restored
    afterwards. `TouchControlsOverlay` draws it in either orientation, over
    `AkvavitEditorBackdrop`.
  - **Nothing in a game changes the defaults or the named layouts.** Madeira's
    `editingEnded` would write a game's edit back into its named layout;
    `editsStayWithGame` makes it the game's own copy instead (except a layout
    just created empty).
  - **Button labels and sticky modifiers** (`AkvavitControlLabels.swift`):
    `AkvavitKeyNames` names the keys Madeira's `keyLabel` left in hex (F1 was
    "70"). `TouchControl.customLabel` and `TouchControl.sticky` are set in the
    mapping panel's row (`AkvavitControlLabelRow`), which also deletes the
    control (the red badge on the button is gone). A sticky Ctrl, Shift or Alt
    button presses its key at the tap and keeps it down until the next key
    button is released (Ctrl, then 1: a control group in AoE II HD); mouse
    taps leave it down, a second tap releases it. An earlier try, a key
    button with modifiers sent together ("Ctrl+1"), did not reach AoE II HD
    and was removed. Touch only; a controller button presses the key as an
    ordinary one. The panel's text field makes the controls window key while
    typing (it is never key otherwise). The user prefers words over symbols
    in the UI.
  - Planned: a Strategy layout, and the type chosen automatically from
    Steam's genres.
- Madeira's host test `tests/host/check-control-presets.py` compiles part of
  `TouchControlPresets.swift`, so it carries stubs for `AkvavitGameControls`
  and `AkvavitBuiltInLayouts`. Three host tests (`check-jit-method`,
  `check-onboarding`, `check-jit-network`) fail since our signing,
  setup-screen and tunnel commits; they still expect Madeira's originals.
  `check-dock-contract` fails on Madeira's base too.
- **Every Wine process runs in the one app process, so Wine's static state in
  the unix side is shared between processes** (RT2 and the Steam client
  through Dock, for example). State that upstream Wine keeps per process
  needs a per-process key here (the process id in the TEB).
  - Found 2026-10-31: the directory listing cache in `ntdll/unix/file.c`
    (`dir_data_cache`). The server numbers its entries per process. With one
    shared array, Steam closing a directory freed the listing RT2 was in, and
    RT2's `FindNextFile` started over. RT2 listed its maps twice and overran
    its scenario buffer: about half of its starts crashed, at random, with
    `c0000005` at `0045E5E8`. Fixed in our Wine (`ios_process_dir_cache`).
    Madeira then says "Madeira Dock exited before a game window appeared",
    although the window had appeared.
  - Look for more such state when a problem only shows with another Wine
    process running alongside.
- **How that bug was found** (useful for similar ones):
  - `env.MADEIRA_VALLOC_LOG_ALL = 1` in `madeira.cfg` logs a 32-bit program's
    allocations (`[valloc]`, `[vfree]`), capped at 3000 lines each.
  - A temporary `ERR` in `NtReadFile` with the path (`fcntl(F_GETPATH)`)
    showed what the game read; comparing a good and a crashing run read by
    read found where they parted. Wine's `ERR` on the unix side doesn't
    understand `%I64x`.
  - `build/wine-i386/build.sh <module>` rebuilds one 32-bit DLL (30 s).
  - Ruled out on the way: settings file, memory ordering (FEX TSO switches),
    CPU count, audio, junk folders, the app build.
- FEX's 32-bit side creates an empty `unix/var/mobile/Containers/Data/
  Application/<id>/Documents/wine/.config/fex-emu/AppConfig` tree in the
  working directory of a 32-bit program (the game's folder) at each app
  install. Harmless, but untidy; not fixed yet (FEX stays untouched; a valid
  config path from outside would be the way).

## Build gotchas

- Mesa 26 needs Python 3.10 or newer, while macOS's `python3` is Xcode's 3.9.
  `build-native.sh` puts a Homebrew python3 first on PATH.
- Build directories store absolute paths. After moving the checkout, do a
  clean rebuild.
- `runtime-components.py verify all` needs `rustc` on PATH (it fingerprints
  the toolchain).
- With the Xcode MCP tools, build in the user's open Xcode window
  (`windowtab-*` workspace). A headless workspace opened by the tools had no
  Apple account and fell back to a wildcard profile.
- "No Accounts" plus wildcard-profile errors about Increased Memory Limit and
  Extended Virtual Addressing mean Xcode has no Apple account signed in. The
  user fixes that in Xcode → Settings → Apple Accounts. Window IDs
  (`windowtab-*`) change when the project is reopened, so list workspaces
  again.
- The built app is `Madeira.app` in DerivedData's `Debug-iphoneos`, next to
  `MadeiraJITHelper.appex`. Don't pick the helper.

## iPhone Duo

- A foldable with two built-in displays. The outer one is 466×678 pt
  (1398×2034 px @3x). The inner one, unfolded, is 669×951 pt (2007×2853 px),
  about iPad-mini size.
- `UIScreen.mainScreen` is always the **outer** display, even when the app runs
  on the inner one. Use the window scene's geometry.
- The iOS 27.1 SDK adds `UIHinge` / `UIHingeInteraction` (hinge state and
  angle). There is no API for spanning both displays.
- Apps built with an SDK older than iOS 27.1 run letterboxed. Madeira's
  official v0.1.3 IPA was built with the iOS 27.0 SDK.
- Apps move between displays on fold and unfold. Never cache the screen or its
  size.
- An "iPhone Duo" simulator (iOS 27.1) exists, but Madeira's native parts are
  device-only.
- On the outer display the safe area leaves out an 84 pt column on the right,
  where iOS draws the status bar, the floating tab bar and the toolbar. A view
  sized to the safe area that wraps other views makes everything drawn there
  untappable (UIKit only delivers a tap inside all ancestors). Madeira's
  `ClaimGamepadEvents` did that; `AkvavitGamepadClaim` claims gamepad events on the
  window instead.
- To find where taps go on the device, log `hitTest` results and each
  ancestor's `point(inside:)` into Madeira's log and copy
  `Documents/madeira-log.txt` with `devicectl device copy from`. The Xcode
  debugger was unreliable with Madeira (LLDB crashed, or didn't attach).

## Toolchain

- Xcode 27.1 (iOS 27.1 SDK), with Homebrew, cmake, ninja, meson and Rust
  (Homebrew rustup).
- Build with the Xcode MCP tools (`BuildProject`), not `xcodebuild`. Re-select
  the **Madeira** scheme and the device before every build, and check the
  built binary's timestamp before installing.
- Install without launching:
  `xcrun devicectl device install app --device <UDID> <path>.app`
- Crash reports: `xcrun devicectl device info files --device <UDID>
  --domain-type systemCrashLogs`. Launching fails with "Locked" while the
  phone is locked.

## Working with the user

- They test on the device themselves and send screenshots. Ask them to
  report exactly what they see.
- They prefer discussing before large or architectural changes.
