#!/usr/bin/env bash
# build-all.sh
#
# Purpose: Full product build inside the builder image: Native AOT binary,
#   icons, then Flatpak bundle when flatpak-builder is available.
# Usage:   ./scripts/build-all.sh [version]
# Needs:   builder image toolchain; flatpak-builder optional in-container
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
cd "$ROOT"

./scripts/build-app.sh Release
./scripts/build-icons.sh

if command -v flatpak-builder >/dev/null 2>&1 || \
   flatpak info --user org.flatpak.Builder >/dev/null 2>&1 || \
   flatpak info org.flatpak.Builder >/dev/null 2>&1; then
    ./scripts/build-flatpak.sh "$VERSION"
else
    echo "flatpak-builder not in this environment; binary only (CI builds Flatpak on the runner)"
fi

echo "=== build-all complete ==="
ls -lah dist/publish/copilot-desktop-gtk dist/flatpak/*.flatpak 2>/dev/null || \
  ls -lah dist/publish/copilot-desktop-gtk
