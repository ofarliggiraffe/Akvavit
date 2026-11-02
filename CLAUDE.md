# Akvavit

A public fork of [Madeira](https://github.com/willfaust/Madeira), which runs
Windows games on iPhone with FEX-Emu, Wine 11.4 and DXMT, with our own changes
on top. The first game is **Railroad Tycoon 3**, and the device is an **iPhone
Duo**. Personal details (device, team, accounts) are in `CLAUDE.local.md`,
which is git-ignored.

There are two apps (since 2026-11-01):
- **Akvavit's own app** (`akvavit/Akvavit`, shown as "Akvavit"). Our code, on
  Madeira's engine. This is where the work goes.
- **Madeira's app** (`app/`, shown as "Madeira"). Madeira's app with our
  hooks, kept for comparison.

Both can be installed side by side. See "Akvavit's own app" below.

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
- Keep Madeira's names (project, targets, scheme `Madeira`, `Madeira.app`).
  Renaming them would conflict on every merge of `project.pbxproj`. Its
  display name is "Madeira" again (it was "Akvavit" until 2026-11-01), so it
  can be told apart from our own app on the device.
- `akvavit/App` (app files), `akvavit/Tunnel` (the tunnel extension, target
  `AkvavitTunnel`). New files are added in Xcode (the project file is ours to
  edit now). Project paths to them start with `../akvavit/`.
- `app/Signing.xcconfig`: the base configuration of both projects (team and
  bundle ID placeholders, then `#include? "Signing.local.xcconfig"`).
  `MADEIRA_BUNDLE_IDENTIFIER` is Madeira's app's; `AKVAVIT_APP_BUNDLE_IDENTIFIER`
  is our own app's (`APP_BUNDLE_ID` in `local.config`, default `BUNDLE_ID` +
  `.app`). The project file must not set `DEVELOPMENT_TEAM` or the bundle IDs itself.
  Xcode writes `DEVELOPMENT_TEAM` into a target when a team is picked in
  Signing & Capabilities, so don't pick one there, and remove it if it appears.
- `akvavit/scripts/setup.sh`: hooks, the `upstream` remote, submodules,
  `Signing.local.xcconfig`, our app's Xcode project (XcodeGen), privacy
  check. Safe to re-run.
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
  madeira-dock stay on Madeira's forks. FEX changes only with the user's OK
  (see Decisions).
- `MADEIRA.md` is Madeira's README (renamed; `README.md` is ours).

## Akvavit's own app (`akvavit/Akvavit`)

- **XcodeGen project.** `project.yml` describes it; `Akvavit.xcodeproj` is
  generated and git-ignored. Run `xcodegen` in `akvavit/Akvavit` after adding,
  moving or deleting files (folders are listed when generating). A file used
  by two targets must be in one group only (Xcode refuses the project
  otherwise). Project-level settings are the ones Madeira's project sets (no
  XcodeGen presets), so Madeira's files compile the same way. Device only.
- **Targets:**
  - `Akvavit`: the app, interface only (`App/`).
  - `AkvavitKit`: our engine layer (`Kit/`), a *static* framework, so
    everything links into the app binary as in Madeira (Madeira's address-space
    code depends on the app's memory layout). The app force-loads it: DXMT and
    Wine look up some symbols at run time (`macdrv_functions`).
  - `AkvavitTunnel`: our VPN extension, shared with Madeira's project.
  - `AkvavitJITHelper`: Madeira's helper, built as `MadeiraJITHelper.appex`,
    the name Madeira's host code looks for.
- **Madeira's C interface** is a Clang module (`Kit/Engine/module.modulemap`
  over Madeira's bridging header). All of AkvavitKit's Swift sees it without an
  import (`-Xfrontend -import-module MadeiraEngine`); that is how Madeira's
  Swift files compile there unchanged. Frameworks can't have a bridging header.
- **AkvavitKit's public API**, which the interface uses:
  - `AkvavitEngine.start()`;
  - `JIT` (pairing, VPN, check, enable);
  - `Session` with `LaunchConfig` (`.direct`, `.desktop`, `.steam(appID:)`;
    `LaunchConfig(game:settings:fitting:)`), plus `quit()`;
  - `Steam` (sign-in, downloads with a queue and cancel-with-cleanup,
    uninstall, Valve's client files);
  - `Games` (one list, `steam:<id>`: installed games from the install
    records, offline, cached in Application Support; owned games, release
    years and playtime from Steam), `Covers` (Steam's CDN, disk cache,
    downsampled);
  - `GameSettingsStore` (per game: x87 on by default, screen size, controls);
  - `SetupFlow` (first-start setup, its JIT chain);
  - `GameSurfaceView` (picture and touch as mouse);
  - `GameOverlay` (interface above the picture);
  - `ControlLayoutStore` (built-in and your control layouts, the global
    haptics switch), `ControlsRuntime` (the layout in play, its touches,
    what goes to the game), `TextBridge` (typing into the game).
  - `GOGAccount` (sign-in, tokens); GOG's games come through `Games`
    (`gog:<product ID>`).
- **GOG** (2026-11-02, in steps; plan in the user's plans folder). Our own
  code from GOG's unofficial endpoints (the ones Galaxy uses), nothing
  copied: Madeira's draft PR #479 vendors another project's GOG client, and
  the user chose to write our own.
  - Sign-in: GOG's page (`auth.gog.com/auth`, Galaxy's public client ID) in
    a web view with a non-persistent store, which stops at
    `embed.gog.com/on_login_success` and hands over `code`;
    `auth.gog.com/token` trades it for an hour's access token and a refresh
    token (Keychain, this device only). Logs (`[gog]`) never carry either.
  - Games: `embed.gog.com/user/data/games` (owned IDs, signed in), then
    `api.gog.com/products?ids=` (50 at a time; `game_type == "game"`,
    Windows in the content system), `gamesdb.gog.com/platforms/gog/
    external_releases/<id>` (vertical cover: `{formatter}` =
    `_glx_vertical_cover`, `{ext}` = `jpg`, 342×482; first release date).
  - Builds: `content-system.gog.com/products/<id>/os/windows/builds?generation=2`
    (no sign-in), each linking a zlib JSON manifest on GOG's CDN
    (`content-system/v2/meta/aa/bb/<hash>`): install folder, depots
    (languages, bitness, `isGogDepot`), dependencies. Depot manifests use the
    same scheme: files in chunks with `md5` and `compressedMd5`, and newer
    builds also pack small files into a container (`sfcRef`). Chunk links
    need sign-in (`secure_link`, 401 without).
  - Apple's Compression `.zlib` is raw deflate: skip zlib's 2-byte header
    and 4-byte checksum.
  - Downloads (`Kit/GOGDownloader.swift`): `secure_link?generation=2&path=/&_version=2`
    per product gives `urls[0]` (`url_format` with `{…}` parameters); a
    chunk is `{path}` + `/aa/bb/<compressedMd5>`. Each chunk is checked by
    compressed and plain md5 and written at its offset, four at once.
    Games go to `drive_c/GOG Games/<installDirectory>`, our records to
    `drive_c/GOG Games/.akvavit/<id>.json` (+ `.files.json`, and
    `.partial.json` for a stopped download, which Install resumes).
  - Starting (`Kit/GOGStart.swift`): no client, no Dock. The game's own
    `goggame-<id>.info` (primary `FileTask`: path, arguments, working
    folder) gives the program; Play writes `drive_c/GOG Games/.akvavit/
    start-<id>.cmd` (UTF-8 with `chcp 65001`, `cd /d`, then `start "" /d`),
    and a desktop session runs it through `cmd.exe /c`. `LaunchConfig.gameFolder`
    tells the loading screen which programs are the game's.
  - What games need (`GOGStart`, `GOGDownloader`; **untested**, no GOG game
    with dependencies tried yet): GOG's catalogue
    (`content-system.gog.com/dependencies/repository?generation=2` → a zlib
    catalogue: `dependencyId`, `readableName`, `executable`, `internal`,
    `manifest`). Their files come through the public `open_link`, whose
    `url_format` has no `{path}` (append `/aa/bb/<compressedMd5>`), and go
    into the game's folder at their depot paths (`__redist/<id>/…`,
    `DOSBOX/…`). What the build supplies is skipped (the Steam rules,
    `AkvavitInstallScripts.available`). The start file runs the rest first,
    writing `installs.result` in Dock's format for the loading screen; at
    the next Play the ones that succeeded go into `dependencies.json`
    (per prefix) and don't run again.
  - One download queue for every store: `Kit/Downloads.swift` (by game ID),
    which `DownloadActivity` reports. A game start stops all downloads.
  - Store logos (covers, the popup's chip): Wikimedia Commons' public-domain
    Steam and GOG logos, made one-colour, as template images.
- **App icon** (the user's choice, option C on the icon canvas): `App/AppIcon.icon`
  (Icon Composer file: background fill with a dark override, the controller
  as a light and a dark layer, glass off), which iOS 26 and later uses, plus
  `App/Assets.xcassets` as the fallback. `scripts/make-app-icon.swift` draws
  all images (Core Graphics, the canvas's coordinates); `icon.json` is hand
  written in Icon Composer's format. XcodeGen needs `fileTypes: icon` to keep
  the `.icon` folder one file. Check a `.icon` with Icon Composer's `ictool`
  (`…/Icon Composer.app/Contents/Executables/ictool <file> --export-image
  --platform iOS --rendition Dark …`). On the phone, dark icons also need the
  home screen's own setting (Edit › Customize: Dark or Automatic), and iOS
  caches icons until a restart.
- **Background downloads** (`Kit/DownloadActivity.swift`): one
  `BGContinuedProcessingTask` (iOS 26, so AkvavitKit targets 26) for the
  download queue, requested at the Install tap, identifier
  `<bundle ID>.download.<unique>`, registered just before submitting. iOS
  draws its Live Activity; the app gives only title, subtitle and progress.
  iOS ends tasks whose progress looks stuck: progress only grows, in whole
  percent, and the text changes only with the step. It stayed expanded in the
  Dynamic Island on the Duo (flicking it small works); there is no API for
  that. Apple has acknowledged that these tasks pause on a locked device.
- **Build and install:** open `akvavit/Akvavit/Akvavit.xcodeproj` in the user's
  Xcode window (not one the tools open in the background: that one has no
  Apple account and falls back to the wildcard profile). Scheme `Akvavit`,
  device re-selected before each build. The product is `Akvavit.app` in
  DerivedData `Akvavit-*/Build/Products/Debug-iphoneos`. Install with
  `devicectl device install app`, as for Madeira. Its data container uses our
  app's bundle ID. Pairing, Steam sign-in and the prefix are its own.
- **What a launch needs from Madeira's engine** (`Kit/Session.swift`; the rest
  of Madeira's ~750-line launch is optional settings, experiments and
  diagnostics):
  1. the JIT pool (`StikJITHelper.allocatePool`), passed on as `WINE_IOS_JIT_*`;
  2. the debugger detached at once;
  3. `wineserver_start`, waiting for `wineserver_is_ready`;
  4. `wine_process_start` with the program in `MADEIRA_EXE`/`MADEIRA_ARGS`.

  Wine seeds a new prefix from the template itself.
- **Windows' desktop** (`explorer.exe /desktop=shell,WxH <command>`) starts
  *one* command line. A program replaces `services.exe` there, it isn't
  appended (Wine starts the services itself). Dock's start does the same.
- **Dock starts** (`Kit/DockStart.swift`):
  1. close our own Steam connection first (one sign-in of an account online);
  2. the one-use sign-in transfer and the game (`MadeiraDock.writeHandoff`,
     `configure`, launch option 0);
  3. one-time installs (`DockInstallers.prepare`; a session may run only those);
  4. `MADEIRA_DOCK_SESSION`, `MADEIRA_CAGE_RELEASE` and
     `MADEIRA_GDI_SHARED_SECTION` (32-bit games).
- **The picture** (`GameLayerHost`) is a raw view on the window, *above* the
  interface. Anything to draw over a game goes in `GameOverlay`'s window. In
  SwiftUI there, a tap on a button and on empty space report the same view.
  So the overlay takes all touches (a menu), or only points the interface
  claims (controls); it can't tell by itself.
- **Touch as mouse** in our app:
  - a tap clicks;
  - a hold of 0.25 s, or a drag past 10 pt, holds the left button from the
    start point;
  - a two- or three-finger tap is a right or middle click;
  - a two-finger drag is the wheel (20 pt a notch);
  - a four-finger tap is the test menu.

  The user found it works better than in Madeira (where hold never worked
  for them).
- **On-screen controls** (2026-11-01, our own from scratch, the user's
  design on the canvas; nothing of Madeira's controls):
  - Model and store in `Kit/ControlLayouts.swift`, `BuiltInLayouts.swift`,
    `ControlLayoutStore.swift` (`akvavit-control-layouts.json` in
    Application Support, lenient decoding). Places are points from the
    nearest edge (or middle) of the **whole display**, not the safe area
    (the user: a game fills the display).
  - In play: `GameOverlay`'s window takes only touches that begin on a
    control (`ControlsInputView.owns`); the rest go to `GameSurfaceView`,
    so a control and the game can be touched at once. Buttons come before
    trackpads where they overlap. A layout can turn touch on the game off
    (shooters); four fingers still open the menu.
  - Engine calls: keys `winios_post_key`; mouse buttons and the wheel
    `winios_pointer` without MOVE (no position); mouse trackpad ABSOLUTE
    moves; aim pad and aim stick relative moves (raw input sees them, so
    mouse-look works); text `winios_try_post_text` (returns 0 when busy:
    retry the same character); controller `winios_gamepad_set_state(0, …)`
    (+y up). The input ring (256 events) drops the *newest* event when
    full, so motion is sent once per display frame (a `CADisplayLink`);
    a lost key-up would leave a key down.
  - Press is held at least 50 ms; Hold toggles; Sticky lets go after the
    next key or click is let go (a click on the game counts). The same key
    from two controls is counted, so it goes up once. Everything held is let
    go when the app resigns active, the menu opens or the session ends.
  - The virtual controller connects when a layout with controller parts is
    first used and stays for the app run (a game finds controllers at its
    start). Portal never reads it (see Portal below; parked).
  - Haptics: a light tap when a control is touched, only if its own switch,
    its layout's and the Controls tab's are all on.
  - The studio and the game screen are locked to landscape
    (`App/OrientationLock.swift`). The studio is a layer in `RootView`, not
    a `fullScreenCover` (that one didn't open until the tab had redrawn).
- **Loading screen** (2026-11-01, the user's option A on the canvas):
  `Kit/StartProgress.swift` decides, `App/LoadingScreen.swift` draws (so the
  look can change alone). It shows from the Play tap. Steps in real order:
  JIT and Steam's client files (Play's own, `App/Play.swift` reports them;
  a failure there offers Back), Windows, one-time installs
  (they run before Dock signs in), Steam (Dock's report), the game. The game
  is up when a visible window that has drawn belongs to a program inside the
  game's own folder, once installs are done; a start without Steam at its
  first frame; the finished list then shows 0.9 s and fades out over the
  game. The loading screen is drawn in `GameOverlay`'s window (under the
  controls), above Windows' screen: hiding Wine's desktop from the app's
  window (every 0.2 s) still let it flash once, as its view is made after
  the start. The picture (`GameLayerHost`) and, on a desktop session, the
  compositor are hidden as well until then. Careful: `winios_compositor_set_hidden(1)` *drops* a
  game-mode session's view, so only desktop sessions call it. A window with a
  title bar from a program outside `C:\windows\` and the game's folder may
  need an answer: "Show it" reveals Windows' screen until it closes. The
  census (`winios_window_census_enable(1)`) runs during a Dock start; at "up"
  it goes to mode 2, which keeps restoring windows first shown minimized.
  Lines tagged `[start]`. The test menu's "Show Windows' screen" is the way
  out if a game's window is missed.
  A problem before the game is up fails its step in the loading screen:
  Back before Windows started (JIT, client files), Close Akvavit after
  (one session per app run). The game screen is a layer in `RootView` from
  the Play tap, not a `fullScreenCover` (that came up only once the session
  had started), and `GameLayerHost` starts hidden (its black covered the
  loading screen).
  The game must stay: its window still there and drawing again 1 s after
  it was first seen (or still there after 4 s if it drew one picture and
  waits); its going away starts the wait over. Anno 1602 drew one GDI frame,
  then hid its window while setting up DirectDraw, and Wine's desktop showed.
  Lines are plain words for players ("Starting game"); details go to the log.
  The app's drawing stalls while JIT turns on and while Windows prepares
  its JIT memory (likely the debugger pausing the process; not measured):
  the spinner is a Core Animation layer (the render server turns it), and
  the shown lines are paced 0.3 s apart so ticks arrive one by one.
- **Logs:** `Documents/madeira-log.txt` copies empty while a game runs, but
  the hard links in `Documents/logs/` copy fine. Our lines are tagged
  `[session]` (with `fps` every 10 s), `[touch]`, `[controls]` and
  `[akvavit-steam]`. Plain `stderr` reaches the file only once a session has
  started (2026-11-01: interface lines written before any game never showed
  up); before that only `LogStore` lines are there.
  The engine's `[xp]` lines (every 250 ms) carry the time, CPU split across
  fast and slow cores, and disk reads, which is enough to compare loading phases.
- **Verified 2026-11-01** on the Duo:
  - JIT with its own pairing ("Pair with Akvavit");
  - the Direct3D cube, and Windows' desktop with Wine's settings;
  - Steam sign-in, Valve's client files, and RT2 downloaded (669 MB in 8 s);
  - RT2 and RT3 through Dock, RT3 at 60 FPS with reduced-precision x87 (its
    texture glitches as in Madeira); loading felt faster than in Madeira, but
    the user measured it as about the same;
  - fold/unfold, and the test menu with Quit.
- **Open:**
  - **Priority: keep the app out of iCloud backups** (the user, 2026-11-01).
    Backups grew huge: the Wine prefix, with every Steam game inside it,
    is in `Documents` and was backed up. iOS has no switch to exclude a
    whole app, so the app marks its own folders (`Documents` and
    `Library/Application Support`, all of each) excluded from backup
    (`isExcludedFromBackup`). The mark is lost when a folder is created
    again, so set it at each start and again after anything that adds or
    removes data: downloads, installs and uninstalls, Repair, a new
    prefix, Wine Mono, logs. For anyone who installs the app, not only
    this device. Not excludable: UserDefaults (`Library/Preferences`, tiny)
    and the Keychain. Caches and tmp are never backed up anyway.
  - Quit should end the game and return to the app rather than close it
    (wait for Wine to stop, then show the app; a second game still needs a
    restart). Madeira can't quit a game either. It belongs with the real
    in-game menu.
  - Launch options other than Steam's first.
  - Per-game settings files.
  - Background downloads.
  - Choosing a game's control layout in its settings (not designed yet;
    the four-finger test menu chooses one meanwhile).

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

- **Our own app on Madeira's engine** (2026-11-01, replacing "keep Madeira's
  app"). The user wants something of their own, and found many problems came
  from Madeira's app.
  - **No copying Madeira.** Our app is our own design and code. Madeira's
    files are only *used*, compiled from where they are, never copied.
  - **`akvavit/Akvavit/PROVENANCE.md` is the strict list** of what is ours and
    what is Madeira's. Keep it exact with every change.
  - **Madeira's components stay for now** and may be replaced later: the
    native engine and glue, the JIT helper, SwiftSteam, Dock.
  - **Madeira's engine-side Swift is compiled in temporarily** (JIT flow,
    Dock helpers, log, config), behind AkvavitKit's API. It is to be replaced
    piece by piece, each checked against the version that works.
- **The user designs the interface.** Don't design screens on your own; build
  only what the user has settled (on the design canvas, since 2026-11-01:
  the tab column, Library, the game popup with its flip and settings side,
  Get games, setup; Settings as one big card, contents still open).
  The Controls tab and studio are designed and built (2026-11-01).
  Everything in `App/Test/` is temporary test screens for checking AkvavitKit;
  the Settings tab holds them until Settings is designed. Not designed yet:
  Settings' contents, the in-game menu (controls, Quit), choosing a game's
  layout in its settings, dark-mode colours (placeholders in
  `App/Theme.swift`).
- **FEX changes are the user's call** (an earlier note here called FEX
  untouchable; the user never set that rule). Upstream FEX-Emu doesn't accept
  AI-generated code (unverified), which only matters for sending changes
  upstream. A change would live in our own fork of FEX, carried across every
  update. Ask before writing FEX code. The first candidate case is the
  hardware breakpoints for AoE II DE (see below).
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
- **Every iPhone and iPad** (the user, 2026-11-01): the interface, and the
  on-screen controls' layouts, are designed for all iPhone and iPad sizes, not
  only the Duo.
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
- Session logs (`Documents/logs/<exe>-<time>.txt`, hard links to that run's
  `madeira-log.txt`) are kept to the newest 40. Madeira pruned only on direct
  starts; Dock starts (ntdll's `madeira_steam_session_log`) now prune too
  (`AkvavitSessionLogs.swift`). They had grown to 91 files, 155 MB.
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
  Our own on-screen controller (2026-11-01, Akvavit's app, parked by the
  user) behaves the same: connected in slot 0 before Portal starts, with
  `joystick 1` saved in Portal's config and the game restarted, Portal's
  process loads `inputsystem.dll`, `SDL2.dll`, Steam's
  `gameoverlayrenderer.dll` and Wine's `XInput1_4.dll`, yet never reads a
  state: no `[xinput] ml2114 first state query` line, no `ml2180` state read.
  (The `wine_xinput_hid_update` thread proves nothing: any query of an empty
  slot 1-3 starts it.) Portal's joystick goes through SDL2, so look there
  next (SDL's XInput detection, or Steam Input taking the device). Try a
  second XInput game (Portal 2) before blaming the transport.
  A game's Controller choice "XInput and DirectInput" doesn't work through
  Dock: it's exported at Play, but Windows programs inherit their environment
  from Steam, which started earlier. DirectInput reads it from there.
- **Fixed-address file mappings in 32-bit programs** (2026-11-02): wow64
  moves the program's address into its guest window before
  `NtMapViewOfSection` (`build/ntdll-unix/virtual_ios.c`), which then checked
  the moved address against the guest's `zero_bits` limit and refused it
  (`STATUS_INVALID_PARAMETER_4`, error 87). Wine's DirectPlay (`dplayx`) maps
  its shared memory at 0x50000000 and falls back only on "invalid address",
  so its `DllMain` failed and Anno 1602 (GOG) exited at start (c0000142).
  Our change checks and limits the guest address inside the window.
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
    So are Steam's .NET Framework runs (`CommonRedist\.NET\…`) once Wine Mono
    is installed: Microsoft's .NET installers fail under Wine (1603), and
    Madeira runs every script in `Steamworks Shared` for every game, so one
    game's .NET package (Valheim's) hit every game's first start.
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
  install. Harmless, but untidy; not fixed yet (a valid config path from
  outside would avoid a FEX change).

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

- Xcode 27.2 (iOS 27.2 SDK, since 2026-11-01), with Homebrew, cmake, ninja,
  meson, Rust (Homebrew rustup) and XcodeGen.
- Build with the Xcode MCP tools (`BuildProject`), not `xcodebuild`. Re-select
  the scheme (**Akvavit**, or **Madeira** for Madeira's app) and the device
  before every build, and check the built binary's timestamp before installing.
- Install without launching:
  `xcrun devicectl device install app --device <UDID> <path>.app`
- Crash reports: `xcrun devicectl device info files --device <UDID>
  --domain-type systemCrashLogs`. Launching fails with "Locked" while the
  phone is locked.

## Working with the user

- They test on the device themselves and send screenshots. Ask them to
  report exactly what they see.
- They prefer discussing before large or architectural changes.
- They design the user interface themselves (see Decisions); until then, only
  bare test screens.
- Time estimates: they found earlier ones far too high for writing code
  ("days" took an hour or two). Estimate in hours of sessions, and say that
  device rounds and unknowns, not code, take the time.
