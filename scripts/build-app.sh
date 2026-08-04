#!/usr/bin/env bash
# build-app.sh
#
# Purpose: Publish the Native AOT, trimmed linux-x64 binary.
# Usage:   ./scripts/build-app.sh [Release|Debug]
# Needs:   dotnet 11 SDK, clang, gtk4/webkitgtk devel libs
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Release}"
RID="linux-x64"
PROJ="${ROOT}/src/CopilotDesktopGtk/CopilotDesktopGtk.csproj"
OUT="${ROOT}/dist/publish"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_ROOT="${DOTNET_ROOT:-/usr/share/dotnet}"
export PATH="${DOTNET_ROOT}:${PATH}"

if ! command -v dotnet >/dev/null 2>&1; then
    echo "error: dotnet not on PATH (DOTNET_ROOT=${DOTNET_ROOT})" >&2
    exit 1
fi

echo "=== dotnet --info ==="
dotnet --info

mkdir -p "$OUT"
rm -rf "$OUT"

echo "=== publish Native AOT (${CONFIG}, ${RID}) ==="
dotnet publish "$PROJ" \
    -c "$CONFIG" \
    -r "$RID" \
    --self-contained true \
    -p:PublishAot=true \
    -p:PublishTrimmed=true \
    -p:TrimMode=partial \
    -p:StripSymbols=true \
    -o "$OUT"

BIN="${OUT}/copilot-desktop-gtk"
test -x "$BIN"
echo "built $BIN ($(du -h "$BIN" | awk '{print $1}'))"
