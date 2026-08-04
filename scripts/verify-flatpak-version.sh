#!/usr/bin/env bash
# verify-flatpak-version.sh
#
# Purpose: Install a .flatpak bundle into a temp FLATPAK_USER_DIR and assert
#   flatpak info Version/License match expectations (CI gate).
# Usage:   ./scripts/verify-flatpak-version.sh <version> <bundle.flatpak>
# CI:      Yes (release.yml).

set -euo pipefail

VERSION="${1:?version required}"
BUNDLE="${2:?bundle path required}"
APP_ID="com.github.sirredbeard.copilot-desktop-gtk"

if [[ ! -f "$BUNDLE" ]]; then
  echo "error: missing bundle $BUNDLE" >&2
  exit 1
fi

export FLATPAK_USER_DIR="${FLATPAK_USER_DIR:-${TMPDIR:-/tmp}/fp-verify-$$}"
rm -rf "$FLATPAK_USER_DIR"
mkdir -p "$FLATPAK_USER_DIR"

flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
# Runtime should already be present in the builder image.
flatpak install -y --noninteractive --user flathub org.gnome.Platform//50 >/dev/null 2>&1 || true
flatpak install -y --noninteractive --user "$BUNDLE"

info="$(flatpak info --user "$APP_ID")"
echo "$info"
echo "$info" | grep -E "^[[:space:]]*Version:[[:space:]]*${VERSION}$" >/dev/null
echo "$info" | grep -E "^[[:space:]]*License:[[:space:]]*MIT$" >/dev/null
echo "verify-flatpak-version ok: ${VERSION} MIT"
