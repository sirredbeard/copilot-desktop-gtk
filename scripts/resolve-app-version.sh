#!/usr/bin/env bash
# resolve-app-version.sh
#
# Purpose: Print the app version from the project sources (csproj Version,
#   else AppConstants.Version). No hard-coded product version in scripts.
# Usage:   ./scripts/resolve-app-version.sh
# Needs:   python3
# CI:      Yes (local scripts and optional release helpers).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - <<'PY' "$ROOT"
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
csproj = (root / "src/CopilotDesktopGtk/CopilotDesktopGtk.csproj").read_text(encoding="utf-8")
m = re.search(r"<Version>(\d+\.\d+\.\d+)</Version>", csproj)
if m:
    print(m.group(1))
    raise SystemExit(0)
app = (root / "src/CopilotDesktopGtk/AppConstants.cs").read_text(encoding="utf-8")
m = re.search(r'public const string Version = "(\d+\.\d+\.\d+)"', app)
if m:
    print(m.group(1))
    raise SystemExit(0)
raise SystemExit("error: could not resolve app version from csproj/AppConstants")
PY
