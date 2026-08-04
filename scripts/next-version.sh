#!/usr/bin/env bash
# next-version.sh
#
# Purpose: Print the next patch version (X.Y.Z) based on the latest GitHub
#   release tag matching v*. Starts at 0.1.0 when none exist.
# Usage:   ./scripts/next-version.sh
# Needs:   gh (preferred) or git tags
# CI:      Yes (release.yml).

set -euo pipefail

latest=""
if command -v gh >/dev/null 2>&1; then
  latest="$(gh release list --limit 100 --json tagName -q '.[].tagName' 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
fi
if [[ -z "$latest" ]]; then
  latest="$(git tag -l 'v*.*.*' --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
fi

if [[ -z "$latest" ]]; then
  echo "0.1.0"
  exit 0
fi

ver="${latest#v}"
IFS=. read -r major minor patch <<< "$ver"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "error: cannot parse version from tag $latest" >&2
  exit 1
fi
echo "${major}.${minor}.$((patch + 1))"
