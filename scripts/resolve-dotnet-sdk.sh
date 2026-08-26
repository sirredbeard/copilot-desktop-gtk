#!/usr/bin/env bash
# resolve-dotnet-sdk.sh
#
# Purpose: Resolve the latest .NET 11 SDK version from Microsoft release
#   metadata (preview, RC, or GA as available). Prints KEY=value lines
#   for DOTNET_SDK_VERSION, DOTNET_SDK_URL, DOTNET_CHANNEL, and
#   DOTNET_INSTALL_METHOD (safe to tee into $GITHUB_OUTPUT).
# Usage:   ./scripts/resolve-dotnet-sdk.sh [outfile]
# Needs:   curl, python3
# CI:      Yes.

set -euo pipefail

OUT="${1:-/dev/stdout}"
META="https://builds.dotnet.microsoft.com/dotnet/release-metadata/11.0/releases.json"

json="$(curl -fsSL --retry 3 "$META")"
version="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("latest-sdk") or "")')"
if [[ -z "$version" ]]; then
    echo "error: could not resolve latest .NET 11 SDK from $META" >&2
    exit 1
fi

url="https://builds.dotnet.microsoft.com/dotnet/Sdk/${version}/dotnet-sdk-${version}-linux-x64.tar.gz"

{
    echo "DOTNET_SDK_VERSION=${version}"
    echo "DOTNET_SDK_URL=${url}"
    echo "DOTNET_CHANNEL=11.0"
    echo "DOTNET_INSTALL_METHOD=tarball-side-load"
} | tee "$OUT"
