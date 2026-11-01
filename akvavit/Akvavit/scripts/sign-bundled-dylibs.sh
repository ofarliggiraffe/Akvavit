#!/bin/bash
# Xcode build phase, after the resources are copied:
#   1. the licence texts bundled with Apple's Metal Shader Converter must be
#      Madeira's current ones (build/stage-licenses.sh copies them);
#   2. the loose dylibs among the resources (d3d12/: the shader converter, gl/:
#      Mesa and MoltenVK) are signed one by one. The app's signature seals
#      them, but dyld only loads a dylib whose own signature is valid.
set -euo pipefail
repo="$SRCROOT/../.."
app="$CODESIGNING_FOLDER_PATH"

for pair in COPYING:LICENSE-MADEIRA-GPL-3.0.txt LICENSE-EXCEPTION.md:LICENSE-MADEIRA-EXCEPTION.txt; do
    source_file="$repo/${pair%%:*}"
    bundled="$app/licenses/${pair##*:}"
    if ! cmp -s "$source_file" "$bundled"; then
        echo "error: $bundled is missing or out of date; run build/stage-licenses.sh"
        exit 1
    fi
done

identity=-
if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${CODE_SIGNING_ALLOWED:-}" != NO ]]; then
    identity="$EXPANDED_CODE_SIGN_IDENTITY"
fi
shopt -s nullglob
for dylib in "$app"/d3d12/*.dylib "$app"/gl/*.dylib; do
    codesign --force --sign "$identity" --timestamp=none "$dylib"
done
