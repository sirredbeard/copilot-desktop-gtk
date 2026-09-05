#!/usr/bin/env bash
# build-patched-webkit.sh
#
# Purpose: Build the bare-minimum WebKitGTK shared libraries + helper
#          process binaries needed to overlay into /app (Canary pattern),
#          from upstream WebKit's own main branch with our out-of-tree
#          drag-and-drop / file-access fork commit cherry-picked on top -
#          not backported onto whatever WebKitGTK version
#          org.gnome.Platform//50 happens to pin (see
#          packaging/webkit-dnd/README.md for why). Both inputs are
#          resolved fresh, every run, by fetch-webkit-dnd-patch.sh -
#          upstream main's current HEAD and the fork branch's current
#          HEAD - so a push to either moving target is picked up on the
#          next call without editing any file.
# Needs:   Runs on the self-hosted Azure VM runner, inside the
#          webkitgtk-dnd-fix-builder image (Fedora 43 - glibc 2.42 matches
#          org.gnome.Platform//50 for ABI compatibility even though the
#          WebKit source itself is newer than what GNOME ships; see
#          packaging/webkit-dnd/README.md). Every other WebKit dependency
#          (icu, soup, gstreamer, jxl, avif, ...) already matches the
#          runtime's own copy exactly EXCEPT libxml2 - Fedora 43 ships
#          2.12.x/soname .2, the runtime ships 2.14.6/soname .16, a real
#          ABI break. Rather than bundling a private libxml2 into the
#          overlay, this script points CMake's FindLibXml2 straight at the
#          org.gnome.Sdk//50 checkout's own headers/library (see the
#          SDK_LIBXML2 resolution below), so the produced binary links
#          against the exact libxml2 soname the runtime will supply at
#          launch - nothing to bundle, nothing to keep in ABI lockstep by
#          hand. The Sdk's own /usr-prefixed .pc file can't be pointed at
#          via PKG_CONFIG_PATH here (it assumes it's mounted at /usr, not
#          true on this Fedora host), so the exact header dir and .so file
#          are passed to CMake directly instead.
#          Needs org.gnome.Sdk//50 pre-installed under
#          FLATPAK_USER_DIR=/var/lib/flatpak-builder-user on the VM host,
#          bind-mounted read-only into this job's container (see
#          .github/workflows/webkit-dnd-rebuild.yml) - the same
#          pre-seeded Sdk/Platform install the app's own Flatpak build
#          already relies on (see .github/copilot-instructions.md).
#          Source+build tree and ccache live under /var/cache/webkit-dnd on
#          host NVMe, bind-mounted into the job container (see
#          .github/workflows/webkit-dnd-rebuild.yml) - the same shared
#          cache the WebKitGTK-DND-Fix runner on this VM already uses.
# Usage:   ./scripts/build-patched-webkit.sh
# Output:  dist/webkit-dnd-artifact/ containing:
#            lib/{libwebkitgtk-6.0.so*,libjavascriptcoregtk-6.0.so*}
#            lib/webkitgtk-6.0/injected-bundle/*
#            libexec/webkitgtk-6.0/{WebKitWebProcess,WebKitNetworkProcess,WebKitGPUProcess}
# CI:      Yes, self-hosted runner only (WebKit compile is too heavy for
#          hosted runners even with this trimmed build).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/dist/webkit-dnd-artifact"

# Persistent, shared host cache - the same /var/cache/webkit-dnd NVMe path
# the WebKitGTK-DND-Fix runner already uses on this VM (see
# .github/workflows/webkit-dnd-rebuild.yml for the bind-mount). SRC is a
# single long-lived git working tree (there is only ever one - upstream
# main + our cherry-picked fix - not one per WebKitGTK version), so an
# unchanged pair of HEADs skips straight to ninja's own incremental
# rebuild against whatever object files already exist there.
CACHE_BASE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
SRC="${CACHE_BASE}/copilot-desktop-gtk-build/webkit-src"

mkdir -p "$(dirname "$SRC")"

echo "=== Resolving upstream main + cherry-picking fork's DND fix ===" >&2
eval "$("${ROOT}/scripts/fetch-webkit-dnd-patch.sh" "$SRC")"
echo "=== Source ready: upstream_main_sha=${upstream_main_sha} fork_head_sha=${fork_head_sha} ===" >&2

rm -rf "$OUT"
mkdir -p "$OUT"/{lib,libexec/webkitgtk-6.0}

# Resolve org.gnome.Sdk//50's own libxml2 (headers + versioned .so) so
# CMake links against the exact soname org.gnome.Platform//50 will
# supply at launch, instead of this builder's own Fedora libxml2 (see
# the header comment above for why the Sdk's .pc file can't just be
# added to PKG_CONFIG_PATH - it assumes it's mounted at /usr). The
# directory name under .../50/ is a content hash that changes whenever
# the Sdk updates, so it's globbed fresh each run rather than pinned.
SDK_USER_DIR="${GNOME_SDK_USER_DIR:-/var/lib/flatpak-builder-user}"
sdk_dirs=("${SDK_USER_DIR}"/runtime/org.gnome.Sdk/x86_64/50/*/files)
if [[ ! -d "${sdk_dirs[0]}" ]]; then
    echo "error: org.gnome.Sdk//50 not found under ${SDK_USER_DIR} - see .github/workflows/webkit-dnd-rebuild.yml for the required bind-mount" >&2
    exit 1
fi
SDK_FILES="${sdk_dirs[0]}"
SDK_LIBXML2_INCLUDE="${SDK_FILES}/include/libxml2"
SDK_LIBXML2_LIB="$(compgen -G "${SDK_FILES}/lib/x86_64-linux-gnu/libxml2.so.*.*" | head -1)"
if [[ ! -d "$SDK_LIBXML2_INCLUDE" || -z "$SDK_LIBXML2_LIB" ]]; then
    echo "error: could not resolve libxml2 headers/library inside ${SDK_FILES}" >&2
    exit 1
fi
echo "=== Linking against org.gnome.Sdk//50's own libxml2: ${SDK_LIBXML2_LIB} ===" >&2

cd "$SRC"

echo "=== Configuring (bare-minimum GTK-port build) ==="
# Shared host ccache, matching the convention already established on this
# VM for the WebKitGTK-DND-Fix runner (/var/cache/webkit-dnd/ccache on host
# NVMe). Both self-hosted runners on this VM see the same host disk, so
# bind-mounting the same path in this job's container (see
# .github/workflows/webkit-dnd-rebuild.yml) genuinely shares compiled
# objects across repos/runners - not a separate, cold cache.
export CCACHE_DIR="${CCACHE_DIR:-/var/cache/webkit-dnd/ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-40G}"
export CCACHE_COMPRESS=1
export CCACHE_BASEDIR="$SRC"
export CCACHE_NOHASHDIR=true
export CCACHE_COMPILERCHECK=content
mkdir -p "$CCACHE_DIR"
command -v ccache >/dev/null 2>&1 && ccache --zero-stats >/dev/null 2>&1 || true

# Mirrors GNOME's own gnome-build-meta cmake-local flags (elements/sdk/
# webkitgtk-6.0.bst) plus trims that only affect dev/test tooling, never
# a feature MainWindow.BuildWebSettings actually turns on:
#   - ENABLE_MINIBROWSER / ENABLE_WEBDRIVER / API tests: unused tooling.
#   - ENABLE_INTROSPECTION off: no public API/ABI changed by this patch,
#     so the runtime's existing WebKit-6.0.typelib is reused as-is.
#   - ENABLE_GTKDOC / ENABLE_DOCUMENTATION off: docs, not shipped.
# Left ON: JIT, WebGL, WebAudio, media/media-stream/encrypted-media,
# WebRTC, clipboard, local storage - everything the app enables at
# runtime, so this is not a feature downgrade vs. the stock runtime build.
# CMAKE_INSTALL_LIBDIR=lib overrides CMake's own Fedora-host default of
# lib64, and LIB_INSTALL_DIR=/app/lib overrides WebKit's own separate
# cache variable of the same intent (WebKit computes its install paths
# from LIB_INSTALL_DIR directly, not from GNUInstallDirs' derived
# CMAKE_INSTALL_LIBDIR, so both must be set) - several install paths
# (notably the injected bundle's own location, which WebKit bakes into
# libwebkitgtk-6.0.so as a compile-time constant, not something resolved
# at runtime) are derived from these variables. Left at their Fedora
# defaults, the binary looks for the bundle under
# /app/lib64/webkitgtk-6.0/injected-bundle/ at launch, but the overlay
# installs flat to /app/lib/ (see the manifest module comment in
# packaging/flatpak/...yml for why) - a mismatch that doesn't crash the
# process, just silently breaks the injected bundle.
mkdir -p build
cd build
# Only run CMake's configure step for a genuinely fresh build directory.
# Re-running `cmake ..` unconditionally here (even when SRC was reused
# as-is because neither upstream HEAD nor the fork HEAD moved) rewrites
# build.ninja and other generated files with fresh timestamps every
# time, which makes ninja treat a large chunk of the tree as stale and
# forces an expensive partial rebuild for no actual source change.
if [[ ! -f build.ninja ]]; then
    CC=clang CXX=clang++ cmake .. \
        -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPORT=GTK \
        -DUSE_GTK4=ON \
        -DENABLE_SPEECH_SYNTHESIS=OFF \
        -DUSE_LIBBACKTRACE=OFF \
        -DENABLE_MINIBROWSER=OFF \
        -DENABLE_WEBDRIVER=OFF \
        -DENABLE_API_TESTS=OFF \
        -DENABLE_INTROSPECTION=OFF \
        -DENABLE_GTKDOC=OFF \
        -DENABLE_DOCUMENTATION=OFF \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_INSTALL_PREFIX=/app \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DLIB_INSTALL_DIR=/app/lib \
        -DLIBXML2_INCLUDE_DIR="$SDK_LIBXML2_INCLUDE" \
        -DLIBXML2_LIBRARY="$SDK_LIBXML2_LIB"
else
    echo "=== build.ninja already exists - skipping CMake reconfigure ===" >&2
fi

echo "=== Building (ninja, $(nproc) jobs) ==="
# WebKitWebProcess/WebKitNetworkProcess/WebKitGPUProcess (the sandboxed
# helper binaries) and the injected bundle are their own ninja targets -
# not part of the WebKit shared-library target - so they must be
# requested explicitly or ninja never links them.
ninja -j"$(nproc)" jsc WebKit WebKitWebProcess WebKitNetworkProcess WebKitGPUProcess libwebkitgtkinjectedbundle.so
command -v ccache >/dev/null 2>&1 && ccache --show-stats || true

echo "=== Staging overlay artifact ==="
LIBDIR="$SRC/build/lib"
find "$LIBDIR" -maxdepth 1 -name 'libwebkitgtk-6.0.so*' -exec cp -a {} "$OUT/lib/" \;
find "$LIBDIR" -maxdepth 1 -name 'libjavascriptcoregtk-6.0.so*' -exec cp -a {} "$OUT/lib/" \;

# No libxml2 to bundle: the -DLIBXML2_INCLUDE_DIR/-DLIBXML2_LIBRARY
# hints above already linked this build against org.gnome.Sdk//50's own
# libxml2.so.16, so the runtime's copy resolves at launch like any other
# WebKit dependency - nothing private to carry alongside the overlay.

mkdir -p "$OUT/lib/webkitgtk-6.0/injected-bundle"
find "$SRC/build" -name 'libwebkitgtkinjectedbundle.so' \
    -exec cp -a {} "$OUT/lib/webkitgtk-6.0/injected-bundle/" \;
for helper in WebKitWebProcess WebKitNetworkProcess WebKitGPUProcess; do
    find "$SRC/build" -name "$helper" -type f \
        -exec cp -a {} "$OUT/libexec/webkitgtk-6.0/" \;
done

echo "=== Artifact staged at $OUT ==="
find "$OUT" -type f -printf '%s %p\n' | sort -n
