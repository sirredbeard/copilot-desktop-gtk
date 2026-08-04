#!/usr/bin/env bash
# lint-all.sh
#
# Purpose: Lint shell scripts, desktop files, and workflow YAML.
# Usage:   ./scripts/lint-all.sh
# Needs:   shellcheck (optional actionlint, desktop-file-validate, python3)
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
rc=0

echo "=== shellcheck ==="
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -t scripts < <(find scripts -type f -name '*.sh' | sort)
    if ((${#scripts[@]} > 0)); then
        shellcheck -x "${scripts[@]}" || rc=1
    fi
else
    echo "shellcheck not installed; skipping"
fi

echo "=== desktop-file-validate ==="
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate assets/desktop/*.desktop || rc=1
else
    echo "desktop-file-validate not installed; skipping"
fi

echo "=== actionlint ==="
if command -v actionlint >/dev/null 2>&1; then
    actionlint .github/workflows/*.yml || rc=1
else
    echo "actionlint not installed; basic YAML parse only"
    python3 - <<'PY' || rc=1
import sys, pathlib
try:
    import yaml  # type: ignore
except Exception:
    yaml = None
paths = list(pathlib.Path('.github/workflows').glob('*.yml'))
if not paths:
    print('no workflows', file=sys.stderr)
    sys.exit(1)
for p in paths:
    text = p.read_text()
    if yaml is not None:
        yaml.safe_load(text)
    else:
        # Minimal sanity: must start with a mapping key and contain 'jobs:'
        if 'jobs:' not in text:
            print(f'{p}: missing jobs:', file=sys.stderr)
            sys.exit(1)
    print(f'ok {p}')
PY
fi

echo "=== Dockerfile / Flatpak sanity ==="
test -f container/Dockerfile
test -f packaging/flatpak/com.github.sirredbeard.copilot-desktop-gtk.yml
grep -q "runtime-version: '50'" packaging/flatpak/com.github.sirredbeard.copilot-desktop-gtk.yml
grep -q 'PublishAot' src/CopilotDesktopGtk/CopilotDesktopGtk.csproj
grep -q 'GirCore.WebKit-6.0' src/CopilotDesktopGtk/CopilotDesktopGtk.csproj

if [[ $rc -ne 0 ]]; then
    echo "lint failed" >&2
    exit "$rc"
fi
echo "lint ok"
