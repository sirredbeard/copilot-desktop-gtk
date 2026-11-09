#!/usr/bin/env bash
# resolve-arch.sh
#
# Purpose: Resolve the target architecture into the names each toolchain
#   wants. Prints KEY=value lines (safe to tee into $GITHUB_OUTPUT or
#   source with sed 's/^/export /', the pattern build-builder-image.sh
#   already uses for resolve-dotnet-sdk.sh).
# Usage:   ./scripts/resolve-arch.sh [outfile] [arch]
#   arch defaults to $COPILOT_ARCH, then `uname -m`. Accepted spellings:
#   x86_64, amd64, x64 for the 64-bit x86 build; aarch64, arm64 for the
#   64-bit Arm build. Anything else is an error: the release ships
#   exactly these two.
# CI:      Yes.
#
# Outputs:
#   COPILOT_ARCH    x86_64 or aarch64 (uname -m / Flatpak spelling)
#   FLATPAK_ARCH    same value; Flatpak and ostree use uname spelling
#   DOTNET_RID      linux-x64 or linux-arm64
#   DOTNET_SDK_ARCH x64 or arm64 (SDK tarball suffix)
#   FEDORA_ARCH     x86_64 or aarch64 (Fedora repo path segment)
#   DOCKER_ARCH     amd64 or arm64 (TARGETARCH / --platform spelling)

set -euo pipefail

OUT="${1:-/dev/stdout}"
ARCH_IN="${2:-${COPILOT_ARCH:-$(uname -m)}}"

case "$ARCH_IN" in
    x86_64|amd64|x64)
        COPILOT_ARCH="x86_64"
        DOTNET_RID="linux-x64"
        DOTNET_SDK_ARCH="x64"
        FEDORA_ARCH="x86_64"
        DOCKER_ARCH="amd64"
        ;;
    aarch64|arm64)
        COPILOT_ARCH="aarch64"
        DOTNET_RID="linux-arm64"
        DOTNET_SDK_ARCH="arm64"
        FEDORA_ARCH="aarch64"
        DOCKER_ARCH="arm64"
        ;;
    *)
        echo "error: unsupported arch '$ARCH_IN' (want x86_64 or aarch64)" >&2
        exit 1
        ;;
esac

FLATPAK_ARCH="$COPILOT_ARCH"

lines="COPILOT_ARCH=${COPILOT_ARCH}
FLATPAK_ARCH=${FLATPAK_ARCH}
DOTNET_RID=${DOTNET_RID}
DOTNET_SDK_ARCH=${DOTNET_SDK_ARCH}
FEDORA_ARCH=${FEDORA_ARCH}
DOCKER_ARCH=${DOCKER_ARCH}"

# tee to /dev/stdout would print every line twice.
if [[ "$OUT" == "/dev/stdout" ]]; then
    printf '%s\n' "$lines"
else
    printf '%s\n' "$lines" | tee "$OUT"
fi
