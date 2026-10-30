#!/usr/bin/env bash
# Builds Madeira's native parts (LLVM, FEX, Wine, DXMT, graphics drivers, the
# Windows DLL farms) by running Madeira's own tools/build-ipa.sh without its
# last step. That step makes an unsigned IPA with xcodebuild; we build and sign
# the app in Xcode instead. The first run takes about an hour on an M2.
#
# Fixed here rather than in Madeira:
#   - Mesa 26 (KosmicKrisp) needs Python 3.10 or newer, but the python3 that
#     macOS puts first on PATH is Xcode's 3.9. A python3 from Homebrew is put
#     in front for the build.
#   - Homebrew's rustup is keg-only, so its bin directory is added to PATH.
#
# Then StikJIT and its idevice library are built from source
# (akvavit/scripts/build-stikjit.sh) instead of using the prebuilt framework.
#
#   JOBS=6 akvavit/scripts/build-native.sh      parallel jobs (default 6: fits 16 GB RAM)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
M="$ROOT"
WORK="$ROOT/.build"
export JOBS="${JOBS:-6}"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$M/tools/build-ipa.sh" ]] || die "Run akvavit/scripts/setup.sh first."

mkdir -p "$WORK/shims" "$WORK/logs"
py=""
for v in 3.14 3.13 3.12 3.11 3.10; do
    if command -v "python$v" >/dev/null; then py="$(command -v "python$v")"; break; fi
done
[[ -n "$py" ]] || die "Python 3.10 or newer is needed: brew install python@3.12"
ln -sf "$py" "$WORK/shims/python3"
export PATH="$WORK/shims:$PATH"

if command -v brew >/dev/null && [[ -d "$(brew --prefix)/opt/rustup/bin" ]]; then
    export PATH="$(brew --prefix)/opt/rustup/bin:$PATH"
fi
command -v cargo >/dev/null || die "Rust is needed: brew install rustup && rustup default stable"

# Madeira's script minus packaging. Generated each run so it follows upstream.
stages="$WORK/build-native-stages.sh"
sed -e "s|^ROOT=.*|ROOT=\"$M\"|" -e '/package-ipa\.sh/d' -e '/Done: /d' "$M/tools/build-ipa.sh" >"$stages"
grep -q "^ROOT=\"$M\"" "$stages" || die "Madeira's build-ipa.sh changed shape (ROOT line); update this script."
! grep -q 'package-ipa' "$stages" || die "Could not remove the packaging step from build-ipa.sh."

log="$WORK/logs/native-$(date +%Y%m%d-%H%M%S).log"
echo "Building with $JOBS jobs, $("$WORK/shims/python3" --version), log: $log"
caffeinate -i bash "$stages" >"$log" 2>&1 || {
    tail -40 "$log" >&2
    die "Native build failed; full log: $log"
}

echo "Verifying the runtime components"
python3 "$M/tools/build/runtime-components.py" verify all

# StikJIT and its idevice library from source, in place of Madeira's prebuilt copy.
"$ROOT/akvavit/scripts/build-stikjit.sh"
echo "Native build done. Build the \"Madeira\" scheme in Xcode for your device."
