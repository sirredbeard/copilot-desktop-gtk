#!/usr/bin/env bash
# stamp-version.sh - thin wrapper around stamp-version.py
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "${ROOT}/scripts/stamp-version.py" "${1:?version required}"
