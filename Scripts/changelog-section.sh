#!/usr/bin/env bash
# Prints the CHANGELOG.md section for one version (without its heading).
#
# Usage: Scripts/changelog-section.sh <version>      e.g. Scripts/changelog-section.sh 0.2.0
#
# Exits 1 when the version has no section so a release can't ship without notes.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:?usage: Scripts/changelog-section.sh <version>}"

section=$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md)

# Trim leading/trailing blank lines.
section=$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

if [[ -z "$section" ]]; then
    echo "CHANGELOG.md has no section for $version" >&2
    exit 1
fi

printf '%s\n' "$section"
