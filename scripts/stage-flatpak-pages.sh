#!/usr/bin/env bash
# stage-flatpak-pages.sh
#
# Purpose: Assemble a GitHub Pages site tree from a Flatpak ostree repo:
#   site/repo (ostree), .flatpakrepo, .flatpakref, index.html, .nojekyll.
# Usage:   ./scripts/stage-flatpak-pages.sh [OSTREE_REPO] [SITE_DIR]
# Env:     PAGES_OWNER, PAGES_REPO, FLATPAK_APP_ID, FLATPAK_APP_TITLE,
#          FLATPAK_BRANCH, FLATPAK_REMOTE_NAME
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OSTREE_REPO="${1:-${ROOT}/dist/flatpak-repo}"
SITE_DIR="${2:-${ROOT}/dist/pages-site}"

OWNER="${PAGES_OWNER:-sirredbeard}"
REPO_NAME="${PAGES_REPO:-copilot-desktop-gtk}"
APP_ID="${FLATPAK_APP_ID:-com.github.sirredbeard.copilot-desktop-gtk}"
APP_TITLE="${FLATPAK_APP_TITLE:-Copilot}"
BRANCH="${FLATPAK_BRANCH:-stable}"
REMOTE_NAME="${FLATPAK_REMOTE_NAME:-$REPO_NAME}"

pages_root="https://${OWNER}.github.io/${REPO_NAME}/"
repo_url="${pages_root}repo/"

if [[ ! -f "$OSTREE_REPO/config" ]]; then
  echo "error: not an ostree repo: $OSTREE_REPO" >&2
  exit 1
fi

rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"
cp -a "$OSTREE_REPO" "$SITE_DIR/repo"

# AppStream screenshot media for GNOME Software.
# Prefer mirrored media from build-flatpak.sh (flatpak-builder --mirror-screenshots-url);
# also keep original assets/screenshots as a stable fallback path.
write_dir_index() {
  local dir="$1"
  local title="$2"
  {
    echo "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>${title}</title></head><body>"
    echo "<h1>${title}</h1><ul>"
    find "$dir" -maxdepth 1 -type f ! -name index.html -printf '%f\n' 2>/dev/null | sort | while read -r b; do
      echo "<li><a href=\"${b}\">${b}</a></li>"
    done
    # one level of subdirs (mirrored appstream media trees)
    find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | while read -r d; do
      echo "<li><a href=\"${d}/\">${d}/</a></li>"
    done
    echo '</ul></body></html>'
  } > "$dir/index.html"
}

if [[ -d "$ROOT/dist/flatpak-media" ]] && [[ -n "$(find "$ROOT/dist/flatpak-media" -type f 2>/dev/null | head -1)" ]]; then
  mkdir -p "$SITE_DIR/media"
  cp -a "$ROOT/dist/flatpak-media/." "$SITE_DIR/media/"
  write_dir_index "$SITE_DIR/media" "media"
  # Nested indexes so deep media paths do not 404 as directories.
  find "$SITE_DIR/media" -type d | while read -r d; do
    write_dir_index "$d" "$(basename "$d")"
  done
fi

if [[ -d "$ROOT/assets/screenshots" ]]; then
  mkdir -p "$SITE_DIR/screenshots"
  cp -a "$ROOT/assets/screenshots/." "$SITE_DIR/screenshots/"
  write_dir_index "$SITE_DIR/screenshots" "screenshots"
fi

{
  echo "# Flatpak ostree refs @ $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# base: $repo_url"
  if command -v ostree >/dev/null 2>&1; then
    ostree --repo="$SITE_DIR/repo" refs 2>/dev/null || true
  fi
  find "$SITE_DIR/repo/refs" -type f 2>/dev/null | sed "s|^$SITE_DIR/repo/||" | sort || true
} > "$SITE_DIR/repo/manifest.txt"

# GPG: prefer freshly exported key from build-flatpak.sh, else packaging/.
GPG_ASC=""
for cand in "${ROOT}/dist/flatpak-repo-public.asc" "${ROOT}/packaging/flatpak-gpg/public.asc"; do
  if [[ -s "$cand" ]]; then
    GPG_ASC="$cand"
    break
  fi
done
GPG_KEY_LINE=""
if [[ -n "$GPG_ASC" ]]; then
  # Flatpak wants one-line base64 of the armored public key.
  GPG_B64="$(base64 -w0 "$GPG_ASC" 2>/dev/null || base64 "$GPG_ASC" | tr -d '\n')"
  GPG_KEY_LINE="GPGKey=${GPG_B64}"
  cp -f "$GPG_ASC" "$SITE_DIR/flatpak-signing-key.asc"
fi

cat > "$SITE_DIR/${REMOTE_NAME}.flatpakrepo" <<REPO
[Flatpak Repo]
Title=${APP_TITLE} (GitHub Pages)
Url=${repo_url}
Homepage=https://github.com/${OWNER}/${REPO_NAME}
Comment=Unofficial ${APP_TITLE} builds. Not affiliated with Microsoft.
Description=Personal Flatpak repository hosted on GitHub Pages for ${APP_ID}.
DefaultBranch=${BRANCH}
${GPG_KEY_LINE}
REPO

# One-shot install that also registers the Pages remote for flatpak update.
cat > "$SITE_DIR/${APP_ID}.flatpakref" <<REF
[Flatpak Ref]
Title=${APP_TITLE}
Name=${APP_ID}
Branch=${BRANCH}
Url=${repo_url}
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
SuggestRemoteName=${REMOTE_NAME}
IsRuntime=false
Homepage=https://github.com/${OWNER}/${REPO_NAME}
Comment=Installs ${APP_TITLE} and adds the GitHub Pages remote for updates.
${GPG_KEY_LINE}
REF

export PAGES_OWNER="$OWNER"
export PAGES_REPO="$REPO_NAME"
export FLATPAK_APP_ID="$APP_ID"
export FLATPAK_APP_TITLE="$APP_TITLE"
export FLATPAK_BRANCH="$BRANCH"
export FLATPAK_REMOTE_NAME="$REMOTE_NAME"
"${ROOT}/scripts/generate-flatpak-repo-index.sh" "$SITE_DIR"

echo "staged Pages site at $SITE_DIR"
find "$SITE_DIR" -maxdepth 2 -type f | head -40
