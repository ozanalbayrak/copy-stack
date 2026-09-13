#!/usr/bin/env bash
# Builds a distributable zip: build/CopyStack-<version>.zip
#
# Usage: Scripts/release.sh <version>      e.g. Scripts/release.sh 0.1.0
#
# Honours the same CODESIGN_IDENTITY as build-app.sh. Prints the SHA-256 of
# the zip so it can be pasted into release notes or a Homebrew cask.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:?usage: Scripts/release.sh <version>}"

VERSION="$version" Scripts/build-app.sh

zip="build/CopyStack-$version.zip"
rm -f "$zip"
# ditto preserves the bundle's resource forks and code signature; plain zip does not.
ditto -c -k --sequesterRsrc --keepParent build/CopyStack.app "$zip"

echo "Built $zip"
shasum -a 256 "$zip"
