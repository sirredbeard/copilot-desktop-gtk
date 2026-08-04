#!/usr/bin/env bash
# next-version.sh
#
# Purpose: Print the next release version (X.Y.Z). Uses the latest GitHub
#   release tag matching v* and bumps patch. When no release tags exist,
#   prints the version from project sources (csproj / AppConstants).
# Usage:   ./scripts/next-version.sh
# Needs:   gh (preferred) or git tags; resolve-app-version.sh
# CI:      Yes (release.yml).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

latest=""
if command -v gh >/dev/null 2>&1; then
  latest="$(gh release list --limit 100 --json tagName -q '.[].tagName' 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
fi
if [[ -z "$latest" ]]; then
  latest="$(git -C "$ROOT" tag -l 'v*.*.*' --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
fi

if [[ -z "$latest" ]]; then
  # First release: ship whatever is already in the sources.
  exec "${ROOT}/scripts/resolve-app-version.sh"
fi

ver="${latest#v}"
IFS=. read -r major minor patch <<< "$ver"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "error: cannot parse version from tag $latest" >&2
  exit 1
fi
echo "${major}.${minor}.$((patch + 1))"
