# Akvavit

**This is [Madeira](https://github.com/willfaust/Madeira), by Will Faust and its
contributors.** Madeira runs Windows PC games on a non-jailbroken iPhone, with
FEX-Emu, Wine and DXMT. All of that work is theirs. Akvavit is a fork that
packages Madeira for building and installing on your own iPhone, with a few
fixes on top. The first target is Railroad Tycoon 3 on an iPhone Duo.

Madeira's own README, which explains how it works, is in [MADEIRA.md](MADEIRA.md).

> [!NOTE]
> This is a personal project in an early state, built on a research project.
> Expect rough edges. The changes are tested on one device.

## What Akvavit changes

- Builds and signs the app with your own developer account and bundle ID, and
  names it Akvavit.
- Works around build problems on a current Mac (Python version for Mesa,
  Homebrew's Rust).
- **JIT without other apps:** a loopback VPN built into the app
  (`akvavit/Tunnel`) replaces LocalDevVPN and the JIT shortcut. Pair the
  iPhone once in setup (Madeira's own in-app pairing, iOS 27), allow the VPN
  once, and Enable JIT works by itself. The VPN only carries traffic to the
  iPhone itself. It stays on by default (Settings › JIT), so JIT also works
  offline. The one rule: JIT can't start while the iPhone uses cellular data,
  so use Wi-Fi, or turn on airplane mode for a moment.
- **StikJIT built from source** (`akvavit/scripts/build-stikjit.sh`):
  StikJIT 1.9.0 and the idevice library inside it (v0.1.68), pinned as
  submodules in `akvavit/vendor`, replace the prebuilt framework Madeira
  ships. The build checks that the result has the same public interface as
  the prebuilt one, and lists the licences of every Rust crate inside it in
  the app's `legal` folder.
- **32-bit OpenGL in Madeira's Wine:** 32-bit programs keep their memory in a
  separate window on iOS, and Wine's generated OpenGL bridge for them didn't
  translate their pointers, so Direct3D 8 games (through wined3d) crashed
  while loading. The generator now emits Madeira's own translation, also for
  OpenGL context handles and function names. The `wine` submodule points to
  [Akvavit's Wine](https://github.com/ofarliggiraffe/wine/tree/akvavit) for
  this.
- **32-bit games at full speed:**
  - A program image whose size isn't a multiple of iOS's 16 KB pages no longer
    ends up in the JIT memory pool, where every write to it was emulated.
  - "Reduced-precision x87" is on by default for 32-bit games, and can still
    be switched off per game.

  Railroad Tycoon 3 went from 1–2 to 60 FPS.
- **16- and 8-bit colour modes** for old DirectDraw games, as on Windows.
  Railroad Tycoon II needs them to start.
- **64-bit programs work in a local build** (Madeira issue #423): the C
  runtimes keep their delay imports.
- **Steam sign-in** survives approving it in the Steam app.
- **Its own setup screens** for JIT, which leave Madeira's Steam, Dock and
  Wine Mono pages as they are.
- **iPhone Duo:** the library's toolbar and tab bar can be tapped on the
  outer display (Madeira's gamepad handling made them untappable there).

Akvavit's own code lives in `akvavit/`. Changes to Madeira's files are kept
small, so updates from Madeira merge easily.

Planned:

- **Older Direct3D and DirectDraw:** open-source wrappers such as d3d8to9 and
  cnc-ddraw, built from source, bundled and applied per game automatically.
- **Foldable support** for the iPhone Duo: resize when folding and unfolding,
  and moving between the two displays.

## Requirements

- macOS with Xcode 27.1 or later (iOS 27.1 SDK), Homebrew, Git, Python 3.10 or
  later from Homebrew, and Rust (`brew install rustup && rustup default stable`).
  The build installs XcodeGen with Homebrew if it's missing.
- A **paid** Apple developer account. The app needs the Increased Memory Limit
  and Extended Virtual Addressing capabilities, and the built-in VPN needs
  Network Extensions.
- About 40 GB of free disk space for the checkout and the build.
- An iPhone on iOS 26 or later; see [MADEIRA.md](MADEIRA.md) for JIT
  requirements.

## Building

```sh
git clone --recurse-submodules https://github.com/ofarliggiraffe/Akvavit.git
cd Akvavit
cp local.config.example local.config   # then fill in your team ID and bundle ID
akvavit/scripts/setup.sh               # hooks, submodules, signing settings
akvavit/scripts/build-native.sh        # about an hour the first time
```

Then open `app/Madeira.xcodeproj` in Xcode, choose the **Madeira** scheme and
your device, and build. Use the Debug configuration: Madeira's docs say Release
builds have crashed games.

Don't use the app's Settings › Signing to re-sign it. It sends your Apple ID
through third-party servers. A build from Xcode with a paid account is valid
for a year.

## Updating from Madeira

```sh
git fetch upstream
git merge upstream/main
```

If Madeira moved its `wine` submodule, merge Madeira's Wine branch
(`madeira-lgpl` of `willfaust/wine`) into Akvavit's `akvavit` branch in
`wine/`. If `dlls/opengl32/unix_thunks.c` conflicts there, take Madeira's
version and run `akvavit/scripts/regen-opengl-thunks.sh`. Then commit the new
`wine` pointer here, and rebuild.

## Keeping personal information out

`local.config` holds your team ID, bundle ID, device UDID and any words that
must never be published. It is git-ignored, and so is
`app/Signing.local.xcconfig`, which `setup.sh` writes from it.
`akvavit/scripts/setup.sh` installs git hooks (`akvavit/githooks`) that run
`akvavit/scripts/check-personal.sh` on every commit, commit message, merge and
push (tags included), with fallback copies in `.git/hooks` in case
`core.hooksPath` is ever unset. The pre-push hook also runs Madeira's own.

The check covers what Akvavit adds on top of Madeira: commits that aren't in
Madeira's history, files that only Akvavit has (whole, binary ones too), and
in Madeira's files only what Madeira's version doesn't already contain. It
refuses:

- the values in `local.config`, which it requires
- device UDIDs, home directory paths (macOS, Linux, Wine), email addresses
  other than noreply ones, Xcode team IDs, device and host names that start
  with someone's name, private keys and access tokens
- files that never belong in the repository: signing material, crash logs,
  Xcode user data, build output, Wine prefixes, Steam login data
- changed copies of Madeira's binary files, which a local build rewrites
- commits and tags whose author, committer or tagger is not a GitHub noreply
  address

A GitHub Actions workflow runs `check-personal.sh --everything` on every push,
with the generic checks. It finds a leak after it has been pushed. The hooks
are what prevent it, so commit and push from a terminal, where they run.

For Claude Code, `.claude/hooks/guard-git.sh` refuses commands that would skip
the hooks (`--no-verify`, `git commit -n`, changing `core.hooksPath`), and
checks the text of `gh` PRs, issues and releases.

## AI-assisted work

Akvavit's changes were written with AI assistance (Claude Code). Like
Madeira's forks, they must not be sent to FEX-Emu, which doesn't accept
AI-generated code. Check each upstream project's contribution policy before
proposing anything to it.

## License

GPL-3.0-or-later, the same as Madeira, including Madeira's
[Converter Exception](LICENSE-EXCEPTION.md). See [LICENSE](LICENSE) and
[CONTRIBUTING.md](CONTRIBUTING.md). Commits are signed off under the
[Developer Certificate of Origin](https://developercertificate.org/).

## Credits

All credit for running Windows games on iOS goes to Madeira and its
contributors (see [MADEIRA.md](MADEIRA.md)), and to the projects it builds on:
FEX-Emu, Wine, DXMT, StikJIT, StikDebug and idevice. Akvavit is not affiliated
with Madeira.
