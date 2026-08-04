#!/usr/bin/env bash
# flatpak-gpg-import.sh — prepare a GPG homedir for Flatpak repo signing.
# Usage:
#   ./scripts/flatpak-gpg-import.sh [--generate]
# Env:
#   FLATPAK_GPG_PRIVATE_KEY  armored private key (CI secret)
#   FLATPAK_GPG_HOME         existing gnupg home to reuse
# Writes:
#   path to GPG home on stdout (last line); exports FLATPAK_GPG_KEY_ID
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUB_DIR="$ROOT/packaging/flatpak-gpg"
GENERATE=0
[[ "${1:-}" == "--generate" ]] && GENERATE=1

if [[ -n "${FLATPAK_GPG_HOME:-}" && -d "${FLATPAK_GPG_HOME}" ]]; then
  HOME_GPG="$FLATPAK_GPG_HOME"
else
  HOME_GPG="$(mktemp -d "${TMPDIR:-/tmp}/flatpak-gpg.XXXXXX")"
  chmod 700 "$HOME_GPG"
  if [[ -n "${FLATPAK_GPG_PRIVATE_KEY:-}" ]]; then
    printf '%s\n' "$FLATPAK_GPG_PRIVATE_KEY" | gpg --homedir "$HOME_GPG" --batch --import
  elif [[ -f "${FLATPAK_GPG_PRIVATE_KEY_FILE:-}" ]]; then
    gpg --homedir "$HOME_GPG" --batch --import "$FLATPAK_GPG_PRIVATE_KEY_FILE"
  elif [[ "$GENERATE" -eq 1 ]]; then
    batch="$(mktemp)"
    cat > "$batch" <<'BATCH'
%echo Generating Flatpak repo signing key
Key-Type: RSA
Key-Length: 4096
Name-Real: copilot-desktop-gtk Flatpak
Name-Email: flatpak-signing@sirredbeard.github.io
Expire-Date: 0
%no-protection
%commit
BATCH
    gpg --homedir "$HOME_GPG" --batch --generate-key "$batch"
    rm -f "$batch"
    KEYID=$(gpg --homedir "$HOME_GPG" --list-keys --with-colons | awk -F: '/^pub/ {print $5; exit}')
    mkdir -p "$PUB_DIR"
    echo "$KEYID" > "$PUB_DIR/keyid.txt"
    gpg --homedir "$HOME_GPG" --armor --export "$KEYID" > "$PUB_DIR/public.asc"
  else
    echo "error: set FLATPAK_GPG_PRIVATE_KEY, FLATPAK_GPG_PRIVATE_KEY_FILE, or FLATPAK_GPG_HOME" >&2
    exit 1
  fi
fi

KEYID=$(gpg --homedir "$HOME_GPG" --list-keys --with-colons | awk -F: '/^pub/ {print $5; exit}')
if [[ -z "$KEYID" ]]; then
  echo "error: no public key in $HOME_GPG" >&2
  exit 1
fi
# Prefer packaging keyid when it matches an imported secret.
if [[ -f "$PUB_DIR/keyid.txt" ]]; then
  want=$(tr -d ' \n' < "$PUB_DIR/keyid.txt")
  if gpg --homedir "$HOME_GPG" --list-secret-keys --with-colons | grep -q "$want"; then
    KEYID="$want"
  fi
fi
echo "$KEYID" > "${HOME_GPG}/.keyid"
echo "flatpak gpg ready key=$KEYID home=$HOME_GPG" >&2
# last line for capture
echo "$HOME_GPG"
