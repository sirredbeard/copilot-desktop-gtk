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
PAGES_ROOT="${PAGES_ROOT%/}/"
APP_ID="${FLATPAK_APP_ID:-com.github.sirredbeard.copilot-desktop-gtk}"
REMOTE_NAME="${FLATPAK_REMOTE_NAME:-$REPO_NAME}"
BRANCH="${FLATPAK_BRANCH:-stable}"
REPO_URL="${PAGES_ROOT}repo/"
FLATPAKREF_URL="${PAGES_ROOT}${APP_ID}.flatpakref"
FLATPAKREPO_URL="${PAGES_ROOT}${REMOTE_NAME}.flatpakrepo"

WORKDIR="${TMPDIR:-/tmp}/flatpak-pages-verify-$$"
mkdir -p "$WORKDIR"

# Prefer the builder image preseeded user dir so we do not re-download GNOME 50.
PRESEED="${FLATPAK_VERIFY_USER_DIR:-/var/lib/flatpak-builder-user}"
if [[ -d "$PRESEED" ]]; then
  export FLATPAK_USER_DIR="$PRESEED"
  CLEAN_USER_DIR=0
else
  export FLATPAK_USER_DIR="$WORKDIR/user"
  mkdir -p "$FLATPAK_USER_DIR"
  CLEAN_USER_DIR=1
fi

cleanup() {
  flatpak uninstall -y --noninteractive --user "$APP_ID" >/dev/null 2>&1 || true
  flatpak remote-delete --user "$REMOTE_NAME" >/dev/null 2>&1 || true
  if [[ "$CLEAN_USER_DIR" == "1" ]]; then
    rm -rf "$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

echo "verify Pages Flatpak install"
echo "  version:    $VERSION"
echo "  pages:      $PAGES_ROOT"
echo "  flatpakref: $FLATPAKREF_URL"
echo "  user dir:   $FLATPAK_USER_DIR"

curl -fsSL "${REPO_URL}config" >/dev/null
curl -fsSL "$FLATPAKREF_URL" | tee "$WORKDIR/app.flatpakref" >/dev/null
curl -fsSL "$FLATPAKREPO_URL" | tee "$WORKDIR/remote.flatpakrepo" >/dev/null
grep -q "^Name=${APP_ID}$" "$WORKDIR/app.flatpakref"
grep -q "^Url=${REPO_URL}" "$WORKDIR/app.flatpakref"
grep -q "^Url=${REPO_URL}" "$WORKDIR/remote.flatpakrepo"

flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if ! flatpak info --user org.gnome.Platform//50 >/dev/null 2>&1; then
  flatpak install -y --noninteractive --user flathub org.gnome.Platform//50
fi

# Unsigned personal stream: register remote with --no-gpg-verify, then install.
# Same end state as accepting an unsigned .flatpakref (SuggestRemoteName).
flatpak remote-delete --user "$REMOTE_NAME" >/dev/null 2>&1 || true
flatpak remote-add --user --no-gpg-verify "$REMOTE_NAME" "$FLATPAKREPO_URL"
flatpak uninstall -y --noninteractive --user "$APP_ID" >/dev/null 2>&1 || true

# Install from the Pages remote (not a .flatpak bundle).
flatpak install -y --noninteractive --user "$REMOTE_NAME" "${APP_ID}//${BRANCH}"

# Also prove the published .flatpakref is well-formed for clients.
grep -q "^SuggestRemoteName=${REMOTE_NAME}$" "$WORKDIR/app.flatpakref"
grep -q "^Branch=${BRANCH}$" "$WORKDIR/app.flatpakref"

flatpak info --user "$APP_ID" | tee "$WORKDIR/info.txt"

if ! grep -E '[[:space:]]*Version:[[:space:]]*'"${VERSION}"'([[:space:]]|$)' "$WORKDIR/info.txt"; then
  echo "error: expected Version: $VERSION" >&2
  exit 1
fi

origin="$(flatpak info --user -o "$APP_ID" 2>/dev/null || true)"
if [[ -z "$origin" ]]; then
  origin="$(awk -F': ' '/Origin:/{print $2; exit}' "$WORKDIR/info.txt" | tr -d '[:space:]')"
fi
echo "origin: $origin"
if [[ "$origin" != "$REMOTE_NAME" ]]; then
  echo "error: origin is '$origin', want Pages remote '$REMOTE_NAME' (not sideload/bundle)" >&2
  exit 1
fi

flatpak remotes --user -d | tee "$WORKDIR/remotes.txt"
if ! grep -E "^${REMOTE_NAME}[[:space:]]" "$WORKDIR/remotes.txt" >/dev/null; then
  echo "error: remote $REMOTE_NAME missing after install" >&2
  exit 1
fi

# flatpak remotes -d: name, title, url, ... (tabs). Prefer that over remote-info.
remote_url="$(awk -F'\t' -v n="$REMOTE_NAME" '$1==n {print $3; exit}' "$WORKDIR/remotes.txt" || true)"
if [[ -z "$remote_url" || "$remote_url" == "-" ]]; then
  remote_url="$(flatpak remote-info --user --show-url "$REMOTE_NAME" 2>/dev/null || true)"
fi
echo "remote url: $remote_url"
case "$remote_url" in
  *"${OWNER}.github.io/${REPO_NAME}/repo"*) ;;
  *)
    echo "error: remote URL does not point at Pages ostree ($remote_url)" >&2
    cat "$WORKDIR/remotes.txt" >&2 || true
    exit 1
    ;;
esac

flatpak remote-ls --user "$REMOTE_NAME" | tee "$WORKDIR/remote-ls.txt"
if ! grep -q "$APP_ID" "$WORKDIR/remote-ls.txt"; then
  echo "error: $APP_ID not listed on remote $REMOTE_NAME" >&2
  exit 1
fi

flatpak update -y --noninteractive --user "$APP_ID"

app_path="$(flatpak info --user -l "$APP_ID" 2>/dev/null || true)"
echo "app location: ${app_path:-unknown}"
if [[ -n "$app_path" && -d "$app_path" ]]; then
  if ! find "$app_path" -name copilot-desktop-gtk -type f | grep -q .; then
    echo "error: binary not found under $app_path" >&2
    exit 1
  fi
fi

echo "OK: Pages remote install of $APP_ID $VERSION (origin=$REMOTE_NAME)"
