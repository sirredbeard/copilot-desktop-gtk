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

# Import GPG before export so flatpak-builder can sign app commits on write.
# Do not blank env GPG_HOME before the presence check (secret names are GPG_*).
_GPG_HOME_IN="${GPG_HOME:-}"
GPG_HOME=""
GPG_KEY_ID=""
BUILDER_GPG_ARGS=()
if [[ -n "${_GPG_HOME_IN}" || -n "${GPG_PRIVATE_KEY:-}" || -n "${GPG_PRIVATE_KEY_FILE:-}" ]]; then
  if [[ -n "${_GPG_HOME_IN}" ]]; then
    export GPG_HOME="${_GPG_HOME_IN}"
  fi
  GPG_HOME="$("${ROOT}/scripts/flatpak-gpg-import.sh")"
  GPG_KEY_ID="$(cat "${GPG_HOME}/.keyid")"
  export GNUPGHOME="$GPG_HOME"
  BUILDER_GPG_ARGS=(--gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOME")
  echo "flatpak-builder will GPG-sign with key $GPG_KEY_ID"
fi

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
    "${BUILDER_GPG_ARGS[@]}" \
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
#
# Critical ordering (0.1.14 regression):
#   Static delta pulls do NOT apply detached .commitmeta. If deltas are
#   generated before tips have ostree.gpgsigs, Flatpak fails with:
#     "GPG verification enabled, but no signatures found"
# even though HTTP .commitmeta and ostree --disable-static-deltas pulls work.
#
# Correct order:
#   1) refresh appstream WITHOUT deltas
#   2) ostree gpg-sign every ref tip (app + appstream2 + screenshots)
#   3) generate static deltas + summary.sig
#   4) re-check tips still signed; prove a delta pull verifies GPG
if [[ -n "$GPG_KEY_ID" ]]; then
  echo "signing Flatpak repo with key $GPG_KEY_ID"

  if ! command -v ostree >/dev/null 2>&1; then
    echo "error: ostree CLI required to GPG-sign appstream/screenshots refs" >&2
    exit 1
  fi

  # Drop stale deltas from the ostree cache so we never ship pre-sign deltas.
  rm -rf "$REPO_DIR/deltas" "$REPO_DIR/delta-indexes"

  # Refresh appstream/summary first WITHOUT static deltas.
  flatpak build-update-repo --prune \
    --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOME" "$REPO_DIR"

  sign_all_tips() {
    mapfile -t REFS < <(ostree --repo="$REPO_DIR" refs | sort -u)
    if [[ "${#REFS[@]}" -eq 0 ]]; then
      echo "error: no ostree refs in $REPO_DIR" >&2
      return 1
    fi
    for ref in "${REFS[@]}"; do
      commit="$(ostree --repo="$REPO_DIR" rev-parse "$ref")"
      echo "gpg-sign ref=$ref commit=$commit"
      ostree --repo="$REPO_DIR" gpg-sign --gpg-homedir="$GPG_HOME" "$commit" "$GPG_KEY_ID"
    done
    flatpak build-sign --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOME" "$REPO_DIR" \
      || true
  }

  sign_all_tips

  # NOW generate static deltas from already-signed tips + resign summary.
  flatpak build-update-repo --generate-static-deltas --prune \
    --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOME" "$REPO_DIR"

  # update-repo may rewrite appstream tips; sign again if needed, but do NOT
  # regenerate deltas after this pass (would race with unsigned tips).
  sign_all_tips
  flatpak build-update-repo \
    --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOME" "$REPO_DIR"

  mapfile -t REFS < <(ostree --repo="$REPO_DIR" refs | sort -u)
  missing=0
  for ref in "${REFS[@]}"; do
    commit="$(ostree --repo="$REPO_DIR" rev-parse "$ref")"
    if ! ostree --repo="$REPO_DIR" show --print-detached-metadata-key=ostree.gpgsigs "$commit" >/dev/null 2>&1; then
      echo "error: missing GPG signature on ref $ref ($commit)" >&2
      missing=1
    fi
  done
  if [[ ! -s "$REPO_DIR/summary.sig" ]]; then
    echo "error: missing $REPO_DIR/summary.sig" >&2
    missing=1
  fi
  if [[ "$missing" -ne 0 ]]; then
    echo "error: one or more refs lack ostree.gpgsigs; refusing unsigned Pages deploy" >&2
    exit 1
  fi

  # Prove the client path Flatpak uses (static deltas + GPG) succeeds.
  VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flatpak-gpg-verify.XXXXXX")"
  VERIFY_REPO="$VERIFY_DIR/repo"
  VERIFY_KEY="$VERIFY_DIR/pub.asc"
  gpg --homedir "$GPG_HOME" --armor --export "$GPG_KEY_ID" > "$VERIFY_KEY"
  ostree --repo="$VERIFY_REPO" init --mode=bare-user-only
  ostree --repo="$VERIFY_REPO" remote add --gpg-import="$VERIFY_KEY" \
    local "file://${REPO_DIR}"
  if ! ostree --repo="$VERIFY_REPO" pull --depth=0 local \
      "app/${APP_ID}/x86_64/${BRANCH}"; then
    echo "error: GPG static-delta pull of app tip failed" >&2
    rm -rf "$VERIFY_DIR"
    exit 1
  fi
  if ! ostree --repo="$VERIFY_REPO" pull --depth=0 local appstream2/x86_64; then
    echo "error: GPG static-delta pull of appstream2 tip failed" >&2
    rm -rf "$VERIFY_DIR"
    exit 1
  fi
  rm -rf "$VERIFY_DIR"
  echo "GPG OK: signed ${#REFS[@]} ref tip(s) + summary.sig + delta-pull verified"

  mkdir -p "${ROOT}/dist"
  gpg --homedir "$GPG_HOME" --armor --export "$GPG_KEY_ID" > "${ROOT}/dist/flatpak-repo-public.asc"
else
  echo "WARNING: no Flatpak GPG key configured; repo will be unsigned" >&2
  echo "WARNING: unprivileged system updates will fail (UNTRUSTED remote)" >&2
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
