#!/usr/bin/env bash
# verify-flatpak-repo-install.sh
#
# Purpose: Install the app from the live GitHub Pages Flatpak remote (not a
#   .flatpak bundle), assert version/origin, and confirm the remote stays
#   configured so flatpak update can see later builds.
# Usage:   ./scripts/verify-flatpak-repo-install.sh <version> [pages_root_url]
# Env:     FLATPAK_APP_ID, FLATPAK_REMOTE_NAME, FLATPAK_BRANCH
# CI:      Yes (post Pages deploy).

set -euo pipefail

VERSION="${1:?usage: $0 VERSION [PAGES_ROOT_URL]}"
OWNER="${PAGES_OWNER:-sirredbeard}"
REPO_NAME="${PAGES_REPO:-copilot-desktop-gtk}"
PAGES_ROOT="${2:-https://${OWNER}.github.io/${REPO_NAME}/}"
# Normalize trailing slash
PAGES_ROOT="${PAGES_ROOT%/}/"
APP_ID="${FLATPAK_APP_ID:-com.github.sirredbeard.copilot-desktop-gtk}"
REMOTE_NAME="${FLATPAK_REMOTE_NAME:-$REPO_NAME}"
BRANCH="${FLATPAK_BRANCH:-stable}"
REPO_URL="${PAGES_ROOT}repo/"
FLATPAKREF_URL="${PAGES_ROOT}${APP_ID}.flatpakref"
FLATPAKREPO_URL="${PAGES_ROOT}${REMOTE_NAME}.flatpakrepo"

WORKDIR="${TMPDIR:-/tmp}/flatpak-pages-verify-$$"
export FLATPAK_USER_DIR="$WORKDIR/user"
mkdir -p "$FLATPAK_USER_DIR"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "verify Pages Flatpak install"
echo "  version:    $VERSION"
echo "  pages:      $PAGES_ROOT"
echo "  flatpakref: $FLATPAKREF_URL"
echo "  user dir:   $FLATPAK_USER_DIR"

# Sanity: Pages is actually serving the ostree + client files.
curl -fsSL "${REPO_URL}config" >/dev/null
curl -fsSL "$FLATPAKREF_URL" | tee "$WORKDIR/app.flatpakref" >/dev/null
curl -fsSL "$FLATPAKREPO_URL" | tee "$WORKDIR/remote.flatpakrepo" >/dev/null
grep -q "^Name=${APP_ID}$" "$WORKDIR/app.flatpakref"
grep -q "^Url=${REPO_URL}$" "$WORKDIR/app.flatpakref" || grep -q "^Url=${REPO_URL}" "$WORKDIR/app.flatpakref"
grep -q "^Url=${REPO_URL}" "$WORKDIR/remote.flatpakrepo"

# Runtime from Flathub (app is not a runtime).
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if ! flatpak info --user org.gnome.Platform//50 >/dev/null 2>&1; then
  flatpak install -y --noninteractive --user flathub org.gnome.Platform//50
fi

# Prefer .flatpakref so SuggestRemoteName registers the Pages remote for updates.
# Unsigned personal stream: add remote with --no-gpg-verify, then install from it
# (same end state as accepting an unsigned flatpakref prompt).
flatpak remote-add --if-not-exists --user --no-gpg-verify \
  "$REMOTE_NAME" "$FLATPAKREPO_URL"

# Also exercise the flatpakref file path (must resolve to same app/remote).
flatpak install -y --noninteractive --user --from "$WORKDIR/app.flatpakref" || \
  flatpak install -y --noninteractive --user "$REMOTE_NAME" "${APP_ID}//${BRANCH}"

# Installed?
flatpak info --user "$APP_ID" >"$WORKDIR/info.txt"
cat "$WORKDIR/info.txt"

# Version
if ! grep -E "[[:space:]]*Version:[[:space:]]*${VERSION}([[:space:]]|$)" "$WORKDIR/info.txt"; then
  echo "error: expected Version: $VERSION" >&2
  exit 1
fi

# Origin must be the Pages remote, not sideload/bundle.
origin="$(flatpak info --user -o "$APP_ID" 2>/dev/null || true)"
if [[ -z "$origin" ]]; then
  origin="$(awk -F': ' '/^Origin:/{print $2; exit}' "$WORKDIR/info.txt" | tr -d '[:space:]')"
fi
echo "origin: $origin"
if [[ "$origin" != "$REMOTE_NAME" ]]; then
  echo "error: origin is '$origin', want Pages remote '$REMOTE_NAME' (not sideload/bundle)" >&2
  exit 1
fi

# Remote still configured and points at Pages ostree URL.
flatpak remotes --user -d >"$WORKDIR/remotes.txt"
cat "$WORKDIR/remotes.txt"
if ! grep -E "^${REMOTE_NAME}\b" "$WORKDIR/remotes.txt" >/dev/null; then
  echo "error: remote $REMOTE_NAME missing after install" >&2
  exit 1
fi
remote_url="$(flatpak remote-info --user --show-url "$REMOTE_NAME" 2>/dev/null || true)"
if [[ -z "$remote_url" ]]; then
  # older flatpak: parse from remotes -d
  remote_url="$(awk -v n="$REMOTE_NAME" '$1==n {print $3; exit}' "$WORKDIR/remotes.txt" || true)"
fi
echo "remote url: $remote_url"
case "$remote_url" in
  *"${OWNER}.github.io/${REPO_NAME}/repo"*) ;;
  *)
    echo "error: remote URL does not point at Pages ostree ($remote_url)" >&2
    exit 1
    ;;
esac

# Update path: remote must list the app (proves metadata pull, not just local install).
flatpak remote-ls --user "$REMOTE_NAME" >"$WORKDIR/remote-ls.txt" || true
cat "$WORKDIR/remote-ls.txt"
if ! grep -q "$APP_ID" "$WORKDIR/remote-ls.txt"; then
  echo "error: $APP_ID not listed on remote $REMOTE_NAME" >&2
  exit 1
fi

# flatpak update should succeed (no-op is fine; failure is not).
flatpak update -y --noninteractive --user "$APP_ID"

# Binary present inside the app runtime dir.
app_path="$(flatpak info --user -l "$APP_ID" 2>/dev/null || true)"
echo "app location: ${app_path:-unknown}"
if [[ -n "$app_path" && -d "$app_path" ]]; then
  test -x "$app_path/files/bin/copilot-desktop-gtk" \
    || test -x "$app_path/bin/copilot-desktop-gtk" \
    || find "$app_path" -name copilot-desktop-gtk -type f | grep -q .
fi

echo "OK: Pages remote install of $APP_ID $VERSION (origin=$REMOTE_NAME)"
