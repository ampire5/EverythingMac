#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --disable-sandbox -c release
bin_dir="$(swift build --disable-sandbox -c release --show-bin-path)"
app_dir="$PWD/build/Network Everything.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/EverythingMac" "$app_dir/Contents/MacOS/EverythingMac"
cp scripts/Info.plist "$app_dir/Contents/Info.plist"
if [[ ! -f build/AppIcon.icns ]]; then
    swift scripts/icon.swift
fi
cp build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$CODE_SIGN_IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -Fq '"Local Code Signing"'; then
    signing_identity="Local Code Signing"
else
    signing_identity="-"
fi
if [[ "$signing_identity" == "-" ]]; then
    echo "Using ad hoc signing; Keychain may ask again after a rebuild."
fi
codesign --force --sign "$signing_identity" --options runtime --timestamp=none --identifier org.networkeverything.mac "$app_dir"
codesign --verify --deep --strict "$app_dir"
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    ditto "$app_dir" "$HOME/Applications/Network Everything.app"
    echo "Installed: $HOME/Applications/Network Everything.app"
else
    echo "Built: $app_dir"
fi
