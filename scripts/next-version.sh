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
cd "$ROOT"

REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$REPO" ]] && command -v gh >/dev/null 2>&1; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  REPO="sirredbeard/copilot-desktop-gtk"
fi

latest=""

# 1) GitHub releases API via gh (explicit -R; works in containers)
if command -v gh >/dev/null 2>&1; then
  latest="$(
    gh release list -R "$REPO" --limit 100 --json tagName \
      -q '.[].tagName' 2>/dev/null \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
      | head -n1 || true
  )"
fi

# 2) REST API fallback (same token gh uses)
if [[ -z "$latest" && -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  token="${GH_TOKEN:-$GITHUB_TOKEN}"
  latest="$(
    curl -fsSL \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${REPO}/releases?per_page=100" \
      | python3 -c 'import json,sys,re
rels=json.load(sys.stdin)
for r in rels:
  t=r.get("tag_name") or ""
  if re.fullmatch(r"v\d+\.\d+\.\d+", t):
    print(t); break' 2>/dev/null || true
  )"
fi

# 3) Local tags
if [[ -z "$latest" ]]; then
  git config --global --add safe.directory "$ROOT" 2>/dev/null || true
  latest="$(
    git tag -l 'v*.*.*' --sort=-v:refname 2>/dev/null \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
      | head -n1 || true
  )"
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
