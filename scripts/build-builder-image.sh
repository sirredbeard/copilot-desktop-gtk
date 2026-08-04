#!/usr/bin/env bash
# build-builder-image.sh
#
# Purpose: Build the local podman image copilot-desktop-gtk-builder, resolving
#   the latest .NET 11 SDK version first, then seed GNOME 50 Flatpak runtimes.
# Usage:   ./scripts/build-builder-image.sh [tag]
# Needs:   podman, network
# CI:      Yes (GH Actions pushes to ghcr.io).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-localhost/copilot-desktop-gtk-builder:latest}"

# shellcheck disable=SC1090,SC1091
source <("${ROOT}/scripts/resolve-dotnet-sdk.sh" /dev/stdout | sed 's/^/export /')

echo "building $TAG with DOTNET_SDK_VERSION=${DOTNET_SDK_VERSION}"

podman build \
    -t "$TAG" \
    -f "${ROOT}/container/Dockerfile" \
    --build-arg "DOTNET_SDK_VERSION=${DOTNET_SDK_VERSION}" \
    "${ROOT}"

echo "built $TAG"
podman image inspect "$TAG" --format '{{.Id}} {{.Size}}'

# Seed Flatpak runtimes (privileged; bwrap). build-push-action cannot do this.
echo "seeding Flatpak GNOME 50 runtimes into $TAG"
cid="$(podman create --privileged "$TAG" sleep infinity)"
podman start "$cid" >/dev/null
podman cp "${ROOT}/scripts/seed-flatpak-runtimes.sh" "$cid":/tmp/seed-flatpak-runtimes.sh
podman exec -e FLATPAK_USER_DIR=/var/lib/flatpak-builder-user "$cid" \
    bash /tmp/seed-flatpak-runtimes.sh
podman commit "$cid" "$TAG"
podman rm -f "$cid" >/dev/null
echo "seeded $TAG"

# Also tag YYYY.MM.DD (UTC) for local parity with GHCR.
DATE_TAG="$(date -u +%Y.%m.%d)"
case "$TAG" in
  *:latest)
    BASE="${TAG%:latest}"
    podman tag "$TAG" "${BASE}:${DATE_TAG}"
    echo "also tagged ${BASE}:${DATE_TAG}"
    ;;
esac

