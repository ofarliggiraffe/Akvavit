#!/bin/bash
# Xcode build phase: puts StikJIT.framework (built from source by
# akvavit/scripts/build-stikjit.sh) into the app's Frameworks folder, where the
# JIT helper extension loads it from (@executable_path/../../Frameworks).
set -euo pipefail
[[ "$PLATFORM_NAME" == iphoneos ]] || exit 0

src="$SRCROOT/../../app/Frameworks/StikJIT.xcframework/ios-arm64/StikJIT.framework"
dst="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/StikJIT.framework"
[[ -d "$src" ]] || { echo "error: $src is missing; run akvavit/scripts/build-stikjit.sh"; exit 1; }

rm -rf "$dst"
mkdir -p "$(dirname "$dst")"
ditto "$src" "$dst"

# An embedded framework needs an Info.plist; the xcframework has none.
plist="$dst/Info.plist"
if [[ ! -f "$plist" ]]; then
    cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>StikJIT</string>
    <key>CFBundleIdentifier</key><string>$PRODUCT_BUNDLE_IDENTIFIER.StikJIT</string>
    <key>CFBundleName</key><string>StikJIT</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>MinimumOSVersion</key><string>26.0</string>
</dict>
</plist>
EOF
    plutil -convert binary1 "$plist"
fi

if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${CODE_SIGNING_ALLOWED:-}" != NO ]]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$dst"
fi
