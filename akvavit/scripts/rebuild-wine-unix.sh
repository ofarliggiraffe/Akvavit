#!/usr/bin/env bash
# Rebuilds only Wine's unix side (Madeira's build/ntdll-unix: ntdll and the unix
# libraries, opengl32's among them, into app/Madeira/libntdll_unix.a; and
# build/win32u-unix, the display and window side, into libwin32u_unix.a), for
# testing changes to those files (in wine/ and build/) without the hour-long
# build-native.sh. Needs a finished build-native.sh run (Wine's build-macos
# configuration). Then build the app in Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
M="$ROOT"
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$M/wine/build-macos/include/config.h" ]] || die "Run akvavit/scripts/build-native.sh once first."
mkdir -p "$ROOT/.build/logs"
log="$ROOT/.build/logs/wine-unix-$(date +%Y%m%d-%H%M%S).log"
echo "Rebuilding Wine's unix side, log: $log"
{ "$M/build/ntdll-unix/build.sh" && "$M/build/win32u-unix/build.sh"; } >"$log" 2>&1 ||
    { tail -30 "$log" >&2; die "Build failed; log: $log"; }
grep -E 'FAILED|libntdll_unix.a:|libwin32u_unix.a' "$log" | tail -4
