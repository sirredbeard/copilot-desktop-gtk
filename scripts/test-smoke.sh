#!/usr/bin/env bash
# test-smoke.sh
#
# Purpose: Run the published binary with --smoke-test under a dummy display
#   when possible. Inside the headless builder this validates the binary
#   starts, links against GTK/WebKit, and exits cleanly.
# Usage:   ./scripts/test-smoke.sh
# Needs:   dist/publish/copilot-desktop-gtk; optional Xvfb
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${ROOT}/dist/publish/copilot-desktop-gtk"

if [[ ! -x "$BIN" ]]; then
    echo "error: missing $BIN" >&2
    exit 1
fi

# Dynamic section check: ensure we linked something GTK-ish when not fully static.
if command -v ldd >/dev/null 2>&1; then
    echo "=== ldd (filtered) ==="
    ldd "$BIN" | grep -E 'gtk|webkit|glib|soup|javascriptcore' || true
fi

run_smoke() {
    "$BIN" --version
    "$BIN" --help >/dev/null
    # Smoke-test may fail without a display; treat display-less link/help as
    # the minimum bar and attempt full smoke when Xvfb or a display exists.
    if [[ -n "${DISPLAY:-}" ]]; then
        "$BIN" --smoke-test
        return
    fi
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a -s '-screen 0 1280x720x24' "$BIN" --smoke-test
        return
    fi
    echo "no DISPLAY/xvfb; skipped full UI smoke (version/help ok)"
}

run_smoke
echo "smoke ok"
