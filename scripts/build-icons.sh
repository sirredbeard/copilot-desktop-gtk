#!/usr/bin/env bash
# build-icons.sh
#
# Purpose: Rasterize the Copilot mark into hicolor icon theme sizes.
# Usage:   ./scripts/build-icons.sh [out-dir]
# Needs:   magick/convert (ImageMagick) or ffmpeg fallback; source PNG in assets/icons
# CI:      Yes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_512="${ROOT}/assets/icons/copilot-512.png"
SRC_FULL="${ROOT}/assets/icons/copilot.png"
OUT="${1:-${ROOT}/dist/icons}"

if [[ -f "$SRC_512" ]]; then
    SRC="$SRC_512"
elif [[ -f "$SRC_FULL" ]]; then
    SRC="$SRC_FULL"
else
    echo "error: no source icon under assets/icons" >&2
    exit 1
fi

mkdir -p "$OUT"
SIZES=(512 256 128 64 48 32)

resize() {
    local size="$1" dest="$2"
    if command -v magick >/dev/null 2>&1; then
        magick "$SRC" -resize "${size}x${size}" "$dest"
    elif command -v convert >/dev/null 2>&1; then
        convert "$SRC" -resize "${size}x${size}" "$dest"
    elif command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -i "$SRC" -vf "scale=${size}:${size}" "$dest" >/dev/null 2>&1
    else
        # Last resort: copy the full image for every size. Ugly but installable.
        cp "$SRC" "$dest"
    fi
}

for s in "${SIZES[@]}"; do
    mkdir -p "${OUT}/hicolor/${s}x${s}/apps"
    resize "$s" "${OUT}/hicolor/${s}x${s}/apps/copilot-desktop-gtk.png"
done


echo "icons staged under $OUT"
