#!/usr/bin/env bash
# seed-flatpak-runtimes.sh
#
# Purpose: Install GNOME 50 Platform/Sdk (+ GL/codecs/locale) into the current
#   environment's FLATPAK_USER_DIR. Used after building the builder image so
#   product Flatpak builds skip multi-GB downloads.
# Usage:   ./scripts/seed-flatpak-runtimes.sh
# CI:      Yes (builder-image.yml post-build seed step).

set -euo pipefail

export FLATPAK_USER_DIR="${FLATPAK_USER_DIR:-/var/lib/flatpak-builder-user}"
mkdir -p "$FLATPAK_USER_DIR"

flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install -y --noninteractive --user flathub \
  org.gnome.Platform//50 \
  org.gnome.Platform.Locale//50 \
  org.gnome.Sdk//50 \
  org.gnome.Sdk.Locale//50 \
  org.freedesktop.Platform.GL.default//25.08 \
  org.freedesktop.Platform.GL.default//25.08-extra \
  org.freedesktop.Platform.codecs-extra//25.08-extra

flatpak list --user
