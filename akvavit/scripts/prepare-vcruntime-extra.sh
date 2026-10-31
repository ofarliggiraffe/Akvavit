#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Microsoft's MFC (mfc140.dll, mfc140u.dll), 32-bit and 64-bit, from Microsoft's official
# Visual C++ 2015-2022 redistributables, unmodified. Madeira's own step
# (tools/build/prepare-vcruntime.sh) takes only the twelve 64-bit C++ runtime DLLs, while
# its session code links MFC too (WineProcessBridge.m, env.MADEIRA_MFC), and nothing gives
# 32-bit games MFC: Age of Empires II HD's launcher imports mfc140u.dll. Wine has no MFC,
# and Steam's Visual C++ installers hang in Akvavit (Microsoft's installer engine), so the
# app supplies it as Madeira supplies the 64-bit runtime:
#
#   app/Madeira/i386-vcruntime/    32-bit MFC, linked into syswow64 (AkvavitVCRuntime.swift)
#   app/Madeira/x86_64-vcruntime/  64-bit MFC, beside Madeira's runtime DLLs
#
# Both are git-ignored: Microsoft's files are never committed. Downloads are cached in
# toolchains/downloads, as Madeira's step caches its own. Run by build-native.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE="$ROOT/toolchains/downloads"
DLLS="mfc140.dll mfc140u.dll"

missing() {   # missing <dest>: true when a DLL is not there yet
    local dll
    for dll in $DLLS; do [[ -f "$1/$dll" ]] || return 0; done
    return 1
}

extract() {   # extract <arch> <machine> <url> <dest>
    local arch="$1" machine="$2" url="$3" dest="$4"
    local exe="$CACHE/vc_redist.$arch.exe"
    if ! missing "$dest"; then
        echo "MFC $arch: cached"
        return
    fi
    command -v 7zz >/dev/null || { echo "ERROR: 7zz is required (brew install sevenzip)" >&2; exit 1; }
    mkdir -p "$CACHE" "$dest"
    if [[ ! -f "$exe" ]]; then
        echo "Downloading the official Microsoft Visual C++ $arch Redistributable..."
        curl --proto '=https' --tlsv1.2 -fL --retry 3 "$url" -o "$exe.part"
        mv "$exe.part" "$exe"
    fi
    local tmp
    tmp="$(mktemp -d)"
    # Microsoft's Burn bundle: the UX container, then the attached one, a CAB whose members
    # are the MSIs and payload CABs. Carve every embedded CAB by its header, as Madeira's step does.
    7zz x -y "$exe" -o"$tmp/redist" >/dev/null || true
    python3 -I - "$exe" "$tmp/redist" <<'PYCAB'
import struct, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
i = 0
while (i := data.find(b"MSCF\0\0\0\0", i)) >= 0:
    size = struct.unpack_from("<I", data, i + 8)[0]
    Path(sys.argv[2], f"carved-{i:x}.cab").write_bytes(data[i:i + size])
    i += 8
PYCAB
    local n=0 cab
    # Nested: payload CABs come out of the attached container, so unpack until none is new.
    for _ in 1 2 3; do
        while IFS= read -r cab; do
            [[ -e "$cab.d" ]] && continue
            mkdir -p "$cab.d"; n=$((n + 1))
            7zz x -y "$cab" -o"$cab.d" >/dev/null 2>&1 || true
        done < <(find "$tmp/redist" -type f -exec sh -c '[ "$(head -c 4 "$1")" = MSCF ]' _ {} \; -print)
    done
    (( n > 0 )) || { rm -rf "$tmp"; echo "ERROR: no CAB payloads inside $exe" >&2; exit 1; }
    # A file is taken by its name (with or without Microsoft's _x86/_amd64 suffix) and its
    # PE machine, so CAB order and other architectures in the package don't matter.
    python3 -I - "$tmp/redist" "$dest" "$machine" $DLLS <<'PYPICK' || { rm -rf "$tmp"; exit 1; }
import shutil, struct, sys
from pathlib import Path
root, dest, machine, names = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3], 16), sys.argv[4:]
def pe_machine(p):
    try:
        d = p.read_bytes()[:4096]
        pe = struct.unpack_from("<I", d, 0x3C)[0]
        return struct.unpack_from("<H", d, pe + 4)[0] if d[:2] == b"MZ" and d[pe:pe + 4] == b"PE\0\0" else None
    except (OSError, struct.error):
        return None
for name in names:
    found = sorted(p for p in root.rglob("*") if p.is_file()
                   and (p.name.lower() == name or p.name.lower().startswith(name + "_"))
                   and pe_machine(p) == machine)
    if not found:
        sys.exit(f"ERROR: {name} (machine {machine:#x}) not found in the redistributable")
    shutil.copyfile(found[0], dest / name)
PYPICK
    rm -rf "$tmp"
    echo "MFC $arch: extracted to $dest"
}

extract x86 14c https://aka.ms/vc14/vc_redist.x86.exe "$ROOT/app/Madeira/i386-vcruntime"
extract x64 8664 https://aka.ms/vc14/vc_redist.x64.exe "$ROOT/app/Madeira/x86_64-vcruntime"
