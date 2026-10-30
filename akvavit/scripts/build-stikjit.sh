#!/usr/bin/env bash
# Builds StikJIT.xcframework from source and puts it in place of the prebuilt one
# Madeira ships (app/Frameworks/StikJIT.xcframework, which Akvavit doesn't track).
#
#   1. idevice's C library (akvavit/vendor/idevice, Rust, tag v0.1.68), the way idevice's
#      own justfile builds it for iOS, but without `obfuscate`, which only hides
#      strings. StikJIT's repository ships this library prebuilt
#      (idevice/libidevice_ffi.a and idevice.h); this replaces both.
#   2. StikJIT (akvavit/vendor/StikJIT, Swift) against that library, the way StikJIT's
#      CI does: XcodeGen, then an archive and an XCFramework.
#
# Both build from copies under .build/stikjit, so the submodules stay clean.
# Two checks against the prebuilt originals: the generated idevice.h, and
# StikJIT's public Swift interface, which is everything Madeira calls.
#
# Needs Rust with the aarch64-apple-ios target, cmake (for aws-lc) and XcodeGen;
# the missing Rust target and XcodeGen are installed. Called by build-native.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/.build/stikjit"
DEST="$ROOT/app/Frameworks/StikJIT.xcframework"
INTERFACE="ios-arm64/StikJIT.framework/Modules/StikJIT.swiftmodule/arm64-apple-ios.swiftinterface"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

if command -v brew >/dev/null && [[ -d "$(brew --prefix)/opt/rustup/bin" ]]; then
    export PATH="$(brew --prefix)/opt/rustup/bin:$PATH"
fi
command -v cargo >/dev/null || die "Rust is needed: brew install rustup && rustup default stable"
command -v cmake >/dev/null || die "cmake is needed: brew install cmake"
rustup target list --installed | grep -qx aarch64-apple-ios || rustup target add aarch64-apple-ios
command -v xcodegen >/dev/null || brew install xcodegen

mkdir -p "$WORK" "$ROOT/.build/logs"
buildlog="$ROOT/.build/logs/stikjit-$(date +%Y%m%d-%H%M%S).log"

log "Checking out StikJIT and idevice at the pinned commits"
git -C "$ROOT" submodule update --init akvavit/vendor/StikJIT akvavit/vendor/idevice
rsync -a --delete --exclude .git --exclude target "$ROOT/akvavit/vendor/idevice/" "$WORK/idevice/"
rsync -a --delete --exclude .git "$ROOT/akvavit/vendor/StikJIT/" "$WORK/StikJIT/"

log "Building idevice's C library (Rust; several minutes the first time)"
(
    cd "$WORK/idevice/ffi"
    BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk iphoneos --show-sdk-path)" \
        IPHONEOS_DEPLOYMENT_TARGET=17.0 CARGO_TARGET_DIR="$WORK/cargo" \
        cargo build --release --locked --target aarch64-apple-ios
) >>"$buildlog" 2>&1 || { tail -30 "$buildlog" >&2; die "idevice failed to build; log: $buildlog"; }

lib="$WORK/cargo/aarch64-apple-ios/release/libidevice_ffi.a"
header="$WORK/idevice/ffi/idevice.h"
if cmp -s "$header" "$ROOT/akvavit/vendor/StikJIT/idevice/idevice.h"; then
    echo "  idevice.h matches the one StikJIT ships"
else
    echo "  WARNING: idevice.h differs from the one StikJIT ships:" >&2
    diff "$ROOT/akvavit/vendor/StikJIT/idevice/idevice.h" "$header" | head -20 >&2 || true
fi
cp "$lib" "$header" "$WORK/StikJIT/idevice/"
# The licences of every crate in that library, in the app's bundled legal folder.
python3 "$ROOT/akvavit/scripts/crate-notices.py" "$WORK/idevice/ffi" \
    "the idevice library inside StikJIT.framework (idevice-ffi, built by Akvavit)" \
    "$ROOT/app/Madeira/legal/LICENSES-stikjit-crates.txt"

log "Building StikJIT against it"
(
    cd "$WORK/StikJIT"
    rm -rf build StikJIT.xcframework
    xcodegen generate --quiet
    xcodebuild archive -project StikJIT.xcodeproj -scheme StikJIT \
        -destination 'generic/platform=iOS' -archivePath build/StikJIT-iOS \
        SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO
    xcodebuild -create-xcframework \
        -framework build/StikJIT-iOS.xcarchive/Products/Library/Frameworks/StikJIT.framework \
        -output StikJIT.xcframework
) >>"$buildlog" 2>&1 || { tail -30 "$buildlog" >&2; die "StikJIT failed to build; log: $buildlog"; }

# The public interface, without comment lines (compiler version, flags).
api() { grep -v '^//' "$1" | grep -v '^\s*$'; }
original="$WORK/original.swiftinterface"
# Madeira's prebuilt copy, at the Madeira commit this checkout is based on.
base="$(git -C "$ROOT" merge-base HEAD upstream/main)" ||
    die "Madeira's upstream/main is missing: run akvavit/scripts/setup.sh"
git -C "$ROOT" show "$base:app/Frameworks/StikJIT.xcframework/$INTERFACE" >"$original"
if diff <(api "$original") <(api "$WORK/StikJIT/StikJIT.xcframework/$INTERFACE") >"$WORK/interface.diff"; then
    echo "  StikJIT's public interface matches the prebuilt one Madeira uses"
else
    echo "  WARNING: StikJIT's public interface differs from the prebuilt one (see $WORK/interface.diff):" >&2
    head -20 "$WORK/interface.diff" >&2
fi

log "Installing StikJIT.xcframework in app/Frameworks"
rm -rf "$DEST"
ditto "$WORK/StikJIT/StikJIT.xcframework" "$DEST"
echo "StikJIT built from source: $DEST (log: $buildlog)"
