#!/usr/bin/env bash
# build-flatpak.sh
#
# Purpose: Build a Flatpak and a single-file .flatpak bundle from the
#   prebuilt Native AOT binary.
# Usage:   ./scripts/build-flatpak.sh [version]  # default: version from csproj
# Needs:   flatpak, flatpak-builder, org.gnome.Sdk//50, dist/publish binary
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" != "" ]]; then
    VERSION="$1"
else
    VERSION="$("${ROOT}/scripts/resolve-app-version.sh")"
fi
APP_ID="com.github.sirredbeard.copilot-desktop-gtk"
MANIFEST="${ROOT}/packaging/flatpak/${APP_ID}.yml"
BUILD_DIR="${ROOT}/dist/flatpak-build"
REPO_DIR="${ROOT}/dist/flatpak-repo"
BUNDLE="${ROOT}/dist/flatpak/${APP_ID}-${VERSION}.flatpak"

if [[ ! -x "${ROOT}/dist/publish/copilot-desktop-gtk" ]]; then
    echo "error: missing AOT binary - run build-app.sh first" >&2
    exit 1
fi

flatpak_builder() {
    if command -v flatpak-builder >/dev/null 2>&1; then
        flatpak-builder "$@"
        return
    fi
    if flatpak info --user org.flatpak.Builder >/dev/null 2>&1 || \
       flatpak info org.flatpak.Builder >/dev/null 2>&1; then
        # Flathub ships the builder as a Flatpak. Needs host FS and an explicit
        # FLATPAK_USER_DIR so it sees the host user install (org.gnome.Sdk)
        # instead of the Builder app's private XDG data dir.
        local user_dir="${FLATPAK_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/flatpak}"
        if [[ ! -d "$user_dir" && -d "$HOME/.local/share/flatpak" ]]; then
            user_dir="$HOME/.local/share/flatpak"
        fi
        flatpak run --command=flatpak-builder \
            --filesystem=host \
            --share=network \
            --talk-name=org.freedesktop.Flatpak \
            --env=FLATPAK_USER_DIR="$user_dir" \
            org.flatpak.Builder "$@"
        return
    fi
    echo "error: install flatpak-builder or org.flatpak.Builder" >&2
    exit 1
}

"${ROOT}/scripts/build-icons.sh" "${ROOT}/dist/icons"

# Ensure runtime/sdk. Builder image seeds GNOME 50; only install on miss.
ensure_runtime() {
    local runtime="$1" sdk="$2"
    if flatpak info --user "$runtime" >/dev/null 2>&1 && \
       flatpak info --user "$sdk" >/dev/null 2>&1; then
        echo "flatpak runtime already present: $runtime + $sdk"
        return 0
    fi
    flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    flatpak install -y --noninteractive --user flathub "$runtime" "$sdk"
}

if ! ensure_runtime org.gnome.Platform//50 org.gnome.Sdk//50; then
    echo "GNOME 50 runtime missing; trying 49" >&2
    ensure_runtime org.gnome.Platform//49 org.gnome.Sdk//49
    tmp_manifest="${ROOT}/dist/flatpak-manifest-49.yml"
    mkdir -p "$(dirname "$tmp_manifest")"
    sed "s/runtime-version: '50'/runtime-version: '49'/" "$MANIFEST" > "$tmp_manifest"
    MANIFEST="$tmp_manifest"
fi

rm -rf "$BUILD_DIR" "$REPO_DIR"
mkdir -p "${ROOT}/dist/flatpak" "$REPO_DIR"

# --disable-rofiles-fuse: some hosts fail rofiles-fuse mount points under /tmp.
# flatpak-builder resolves source paths relative to the manifest directory.
flatpak_builder --force-clean --user --disable-rofiles-fuse --repo="$REPO_DIR" \
    --state-dir="${ROOT}/dist/flatpak-state" \
    "$BUILD_DIR" \
    "$MANIFEST"

flatpak build-bundle "$REPO_DIR" "$BUNDLE" "$APP_ID" --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
echo "bundle: $BUNDLE ($(du -h "$BUNDLE" | awk '{print $1}'))"
