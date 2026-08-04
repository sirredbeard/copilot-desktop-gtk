#!/usr/bin/env bash
# podman-build-local.sh
#
# Purpose: Pull or build the builder image, then compile and package inside it.
# Usage:   ./scripts/podman-build-local.sh [--pull-ghcr] [version]
# Needs:   podman
# CI:      No (local developer path).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PULL=0
VERSION="0.1.0"
LOCAL_TAG="localhost/copilot-desktop-gtk-builder:latest"
GHCR_TAG="ghcr.io/sirredbeard/copilot-desktop-gtk-builder:latest"

for arg in "$@"; do
    case "$arg" in
        --pull-ghcr) PULL=1 ;;
        *) VERSION="$arg" ;;
    esac
done

IMAGE="$LOCAL_TAG"
if [[ "$PULL" -eq 1 ]]; then
    echo "pulling $GHCR_TAG"
    if podman pull "$GHCR_TAG"; then
        IMAGE="$GHCR_TAG"
    else
        echo "pull failed; falling back to local build" >&2
        "${ROOT}/scripts/build-builder-image.sh" "$LOCAL_TAG"
        IMAGE="$LOCAL_TAG"
    fi
elif ! podman image exists "$LOCAL_TAG"; then
    "${ROOT}/scripts/build-builder-image.sh" "$LOCAL_TAG"
    IMAGE="$LOCAL_TAG"
fi

echo "using builder image: $IMAGE"
mkdir -p "${ROOT}/dist"

# privileged: flatpak-builder needs bwrap/proc. label=disable for volume SELinux.
podman run --rm --privileged \
    --security-opt label=disable \
    -v "${ROOT}:/src:Z" \
    -w /src \
    -e COPILOT_RELEASE="${COPILOT_RELEASE:-1}" \
    -e FLATPAK_USER_DIR="${FLATPAK_USER_DIR:-/var/lib/flatpak-builder-user}" \
    "$IMAGE" \
    bash -lc "./scripts/build-all.sh \"$VERSION\" && ./scripts/build-flatpak.sh \"$VERSION\""

podman run --rm --privileged \
    --security-opt label=disable \
    -v "${ROOT}:/src:Z" \
    -w /src \
    "$IMAGE" \
    ./scripts/lint-all.sh

podman run --rm --privileged \
    --security-opt label=disable \
    -v "${ROOT}:/src:Z" \
    -w /src \
    "$IMAGE" \
    ./scripts/test-smoke.sh

echo "local podman build finished"
