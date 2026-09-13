#!/usr/bin/env bash
# Builds build/CopyStack.app from the Swift package.
#
# Usage: Scripts/build-app.sh [--debug]
#
# Environment:
#   CODESIGN_IDENTITY  Identity passed to codesign. Defaults to "-" (ad-hoc).
#                      Use an "Apple Development: ..." identity to keep the
#                      Accessibility grant across rebuilds.
#   VERSION            If set, stamped into CFBundleShortVersionString and
#                      CFBundleVersion (used by Scripts/release.sh).
set -euo pipefail

cd "$(dirname "$0")/.."

config=release
if [[ "${1:-}" == "--debug" ]]; then
    config=debug
fi

swift build -c "$config"

binary="$(swift build -c "$config" --show-bin-path)/CopyStack"
app="build/CopyStack.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/CopyStack"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$app/Contents/Info.plist"
fi
printf 'APPL????' > "$app/Contents/PkgInfo"

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app"

echo "Built $app"
