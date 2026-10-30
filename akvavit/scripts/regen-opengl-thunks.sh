#!/usr/bin/env bash
# Regenerates Wine's opengl32 thunks (wine/dlls/opengl32/unix_thunks.c) with its
# make_opengl, which Akvavit changed to translate 32-bit guest pointers on iOS. Run
# it after changing make_opengl, or after merging Madeira's Wine when unix_thunks.c
# conflicts: take Madeira's version of the file, then run this and commit the result
# in wine/. A normal build needs neither the network nor this script.
#
# make_opengl reads Khronos's registry files at pinned commits from a cache and
# fetches them with wget, which macOS lacks; they are fetched here with curl
# into .build/wine-cache first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
W="$ROOT/wine"
GEN="$W/dlls/opengl32/make_opengl"
CACHE="$ROOT/.build/wine-cache"
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

grep -q 'ios_wow_host_ptr' "$GEN" || die "$GEN has no iOS guest-pointer translation (not Akvavit's Wine?)."

ogl=$(sed -n 's/^my \$ogl_commit="\([0-9a-f]*\)";/\1/p' "$GEN")
egl=$(sed -n 's/^my \$egl_commit="\([0-9a-f]*\)";/\1/p' "$GEN")
[[ -n "$ogl" && -n "$egl" ]] || die "make_opengl's pinned registry commits not found."
mkdir -p "$CACHE/wine"
u=https://raw.githubusercontent.com/KhronosGroup
for pair in "registry-$ogl.py|OpenGL-Registry/$ogl/extensions/registry.py" \
            "gl-$ogl.xml|OpenGL-Registry/$ogl/xml/gl.xml" \
            "wgl-$ogl.xml|OpenGL-Registry/$ogl/xml/wgl.xml" \
            "egl-$egl.xml|EGL-Registry/$egl/api/egl.xml"; do
    file="${pair%%|*}"
    [[ -s "$CACHE/wine/$file" ]] || curl -fsSL -o "$CACHE/wine/$file" "$u/${pair#*|}"
done

(cd "$W/dlls/opengl32" && XDG_CACHE_HOME="$CACHE" perl ./make_opengl)
others=$(git -C "$W" status --short -- dlls/opengl32 include/wine/wgl.h |
         grep -vE 'make_opengl|unix_thunks\.c|unix_private\.h|unix_wgl\.c' || true)
[[ -z "$others" ]] || die "make_opengl changed more than unix_thunks.c:"$'\n'"$others"
echo "Regenerated wine/dlls/opengl32/unix_thunks.c ($(grep -c 'ios_wow_host_ptr' "$W/dlls/opengl32/unix_thunks.c") translated uses)"
git -C "$W" status --short -- dlls/opengl32/unix_thunks.c
