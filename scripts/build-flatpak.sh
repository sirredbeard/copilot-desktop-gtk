#!/usr/bin/env bash
# build-flatpak.sh
#
# Purpose: Build a Flatpak into an ostree repo and a single-file .flatpak bundle
#   from the prebuilt Native AOT binary.
# Usage:   ./scripts/build-flatpak.sh [version]  # default: version from csproj
# Needs:   flatpak, flatpak-builder, org.gnome.Sdk//50, dist/publish binary
# CI:      Yes.
#
# REPO_DIR (dist/flatpak-repo) is reused when it already looks like an ostree
# repo so release CI can cache history and generate static deltas for updates.

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
BRANCH="${FLATPAK_BRANCH:-stable}"

# Keep AppStream release version in sync with the bundle name.
"${ROOT}/scripts/stamp-version.sh" "$VERSION"

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

rm -rf "$BUILD_DIR"
mkdir -p "${ROOT}/dist/flatpak" "$REPO_DIR"

# Reuse an existing ostree repo (CI cache). Only wipe when forced.
if [[ "${FLATPAK_REPO_RESET:-0}" == "1" ]]; then
    rm -rf "$REPO_DIR"
    mkdir -p "$REPO_DIR"
elif [[ -f "$REPO_DIR/config" ]]; then
    echo "reusing ostree repo at $REPO_DIR"
else
    mkdir -p "$REPO_DIR"
fi

PAGES_OWNER="${PAGES_OWNER:-sirredbeard}"
PAGES_REPO="${PAGES_REPO:-copilot-desktop-gtk}"
# AppStream media base on GitHub Pages. Without compose-url-policy=full,
# flatpak-builder's default "partial" policy drops absolute screenshot URLs
# from the repo catalog and GNOME Software shows "No Screenshots".
MEDIA_BASE_URL="${FLATPAK_MEDIA_BASE_URL:-https://${PAGES_OWNER}.github.io/${PAGES_REPO}/media}"

# --disable-rofiles-fuse: some hosts fail rofiles-fuse mount points under /tmp.
# flatpak-builder resolves source paths relative to the manifest directory.
# --default-branch aligns export with manifest branch: stable.
# --mirror-screenshots-url downloads metainfo screenshots into the build and
# rewrites them under MEDIA_BASE_URL so Software can fetch thumbnails.
# --compose-url-policy=full keeps absolute screenshot URLs in appstream.
flatpak_builder --force-clean --user --disable-rofiles-fuse \
    --repo="$REPO_DIR" \
    --default-branch="$BRANCH" \
    --state-dir="${ROOT}/dist/flatpak-state" \
    --compose-url-policy=full \
    --mirror-screenshots-url="$MEDIA_BASE_URL" \
    "$BUILD_DIR" \
    "$MANIFEST"

# Publish mirrored AppStream media for Pages. flatpak-builder + appstreamcli
# compose write screenshots under files/share/app-info/media/... and rewrite
# catalog URLs to MEDIA_BASE_URL + that relative path.
MEDIA_OUT="${ROOT}/dist/flatpak-media"
rm -rf "$MEDIA_OUT"
mkdir -p "$MEDIA_OUT"
MEDIA_SRC=""
for cand in \
    "$BUILD_DIR/files/share/app-info/media" \
    "$BUILD_DIR/screenshots" \
    "${ROOT}/dist/flatpak-state/screenshots"; do
    if [[ -d "$cand" ]] && [[ -n "$(find "$cand" -type f 2>/dev/null | head -1)" ]]; then
        MEDIA_SRC="$cand"
        break
    fi
done
if [[ -n "$MEDIA_SRC" ]]; then
    cp -a "$MEDIA_SRC/." "$MEDIA_OUT/"
    echo "mirrored appstream media ($MEDIA_SRC) -> $MEDIA_OUT"
    find "$MEDIA_OUT" -type f | head -40
else
    echo "warning: no mirrored media dir; copying assets/screenshots" >&2
    mkdir -p "$MEDIA_OUT/screenshots"
    cp -a "${ROOT}/assets/screenshots/." "$MEDIA_OUT/screenshots/" 2>/dev/null || true
fi

# GPG-sign the OSTree repo so system Flatpak installs can update without
# root (avoids "untrusted non-gpg verified remote" via the system helper).
GPG_HOME=""
GPG_KEY_ID=""
if [[ -n "${FLATPAK_GPG_HOME:-}" || -n "${FLATPAK_GPG_PRIVATE_KEY:-}" || -n "${FLATPAK_GPG_PRIVATE_KEY_FILE:-}" ]]; then
  GPG_HOME="$("${ROOT}/scripts/flatpak-gpg-import.sh")"
  GPG_KEY_ID="$(cat "${GPG_HOME}/.keyid")"
  export GNUPGHOME="$GPG_HOME"
  echo "signing Flatpak repo with key $GPG_KEY_ID"
  flatpak build-sign --gpg-sign="$GPG_KEY_ID" "$REPO_DIR" || {
    # Older hosts: sign via ostree directly.
    ostree --repo="$REPO_DIR" gpg-sign "$GPG_KEY_ID" --gpg-homedir="$GPG_HOME" $(ostree --repo="$REPO_DIR" refs) || true
  }
  # Sign summary + static deltas.
  flatpak build-update-repo --generate-static-deltas --prune     --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOME" "$REPO_DIR"
  # Export public key next to repo for stage-flatpak-pages.
  mkdir -p "${ROOT}/dist"
  gpg --homedir "$GPG_HOME" --armor --export "$GPG_KEY_ID" > "${ROOT}/dist/flatpak-repo-public.asc"
else
  echo "WARNING: no Flatpak GPG key configured; repo will be unsigned" >&2
  echo "WARNING: unprivileged system updates will fail (UNTRUSTED remote)" >&2
  # Static deltas make Pages pulls practical (many small objects otherwise).
  flatpak build-update-repo --generate-static-deltas --prune "$REPO_DIR"
fi

# --repo-url embeds the ostree remote in the bundle so install (CLI or GNOME
# Software) can register it for updates. Without this, sideload shows
# "No Software Repository Included" and Origin stays sideload.
REPO_URL="${FLATPAK_REPO_URL:-https://${PAGES_OWNER}.github.io/${PAGES_REPO}/repo/}"
flatpak build-bundle "$REPO_DIR" "$BUNDLE" "$APP_ID" "$BRANCH" \
    --repo-url="$REPO_URL" \
    --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
echo "bundle: $BUNDLE ($(du -h "$BUNDLE" | awk '{print $1}'))"
echo "repo:   $REPO_DIR"
echo "repo-url (embedded): $REPO_URL"
echo "media-base: $MEDIA_BASE_URL"
