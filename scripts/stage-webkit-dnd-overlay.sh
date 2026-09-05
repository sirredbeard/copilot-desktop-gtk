#!/usr/bin/env bash
# stage-webkit-dnd-overlay.sh
#
# Purpose: Place a built (or cache-restored) webkit-dnd-artifact tree at
#          dist/webkit-dnd-overlay/, the path the "webkit-dnd-overlay"
#          flatpak-builder module (packaging/flatpak manifest) installs
#          from. Kept as its own tiny step so release.yml can populate
#          this from a GitHub Actions cache hit without re-running the
#          WebKit build at all.
# Usage:   ./scripts/stage-webkit-dnd-overlay.sh [artifact_dir]
#          Defaults to dist/webkit-dnd-artifact (build-patched-webkit.sh's
#          output).
# CI:      Yes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-${ROOT}/dist/webkit-dnd-artifact}"
DEST="${ROOT}/dist/webkit-dnd-overlay"

if [[ ! -d "$SRC" ]]; then
    echo "error: $SRC does not exist (nothing to stage)" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/

echo "=== Staged overlay at $DEST ==="
find "$DEST" -type f -printf '%s %p\n' | sort -n
