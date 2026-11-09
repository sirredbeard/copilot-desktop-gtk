# copilot-desktop-gtk-builder
#
# Azure Linux 4 base, Fedora 43 repos for GTK4/WebKit devel, side-loaded
# .NET 11 SDK, and Flatpak builder tooling. ARG DOTNET_SDK_VERSION below
# is a fallback pin. CI and ./scripts/build-builder-image.sh pass the
# latest SDK from resolve-dotnet-sdk.sh. Rebuilt weekly via
# builder-image.yml.
#
# Build:  ./scripts/build-builder-image.sh
# Run:    ./scripts/podman-build-local.sh
#
# One Dockerfile builds both arches. The Azure Linux 4 base is a
# multi-arch manifest (amd64 + arm64), TARGETARCH picks the Fedora repo
# arch, the gcc triple prefix, and the .NET SDK tarball for the image
# being built. CI builds each arch on a runner of that arch
# (builder-image.yml); a local podman build builds the host arch.

FROM mcr.microsoft.com/azurelinux-beta/base/core:4.0

ARG DOTNET_SDK_VERSION=11.0.100-preview.7.26381.103
ARG FEDORA_RELEASE=43
# Predefined build arg (amd64 or arm64); declared so RUN steps can read it.
ARG TARGETARCH

LABEL org.opencontainers.image.title="copilot-desktop-gtk-builder" \
      org.opencontainers.image.description="Azure Linux 4 + .NET 11 + Flatpak builder for copilot-desktop-gtk" \
      org.opencontainers.image.source="https://github.com/sirredbeard/copilot-desktop-gtk" \
      org.opencontainers.image.licenses="MIT"

ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    PATH="/usr/share/dotnet:/usr/local/bin:${PATH}" \
    LANG=C.UTF-8 \
    FLATPAK_USER_DIR=/var/lib/flatpak-builder-user

# Base tooling from Azure Linux.
# coreutils-single ships in the image; do not pull full coreutils (conflict).
RUN tdnf -y update && \
    tdnf -y install \
        ca-certificates \
        curl \
        tar \
        gzip \
        xz \
        bzip2 \
        git \
        findutils \
        which \
        binutils \
        glibc-devel \
        kernel-headers \
        make \
        diffutils \
        python3 \
        gawk \
        sed \
        grep \
        shadow-utils \
        util-linux \
        patch \
        file \
    && tdnf clean all

# Fedora 43 repos for GTK/WebKit/Flatpak packages not on AZL4 container images.
# Written with printf (not Dockerfile heredoc) so container builders do not
# treat [fedora43] as a Dockerfile instruction. The repo path segment is
# the Fedora arch for TARGETARCH: x86_64 for amd64, aarch64 for arm64.
RUN fa=x86_64; \
    if [ "${TARGETARCH:-amd64}" = "arm64" ]; then fa=aarch64; fi; \
    printf '%s\n' \
      '[fedora43]' \
      "name=Fedora 43 Everything ${fa}" \
      "baseurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/${fa}/os/" \
      'enabled=1' \
      'gpgcheck=0' \
      'cost=50' \
      '' \
      '[fedora43-updates]' \
      "name=Fedora 43 Updates ${fa}" \
      "baseurl=https://dl.fedoraproject.org/pub/fedora/linux/updates/43/Everything/${fa}/" \
      'enabled=1' \
      'gpgcheck=0' \
      'cost=50' \
      > /etc/yum.repos.d/fedora-builder.repo

# Desktop stack + AOT link toolchain.
RUN tdnf -y install \
        clang \
        gcc \
        gcc-c++ \
        libgcc \
        zlib-devel \
        make \
        pkgconf \
        pkgconf-pkg-config \
        gtk4 \
        gtk4-devel \
        gtk3 \
        gtk3-devel \
        libadwaita \
        libadwaita-devel \
        webkitgtk6.0 \
        webkitgtk6.0-devel \
        gobject-introspection \
        gobject-introspection-devel \
        glib2-devel \
        cairo-devel \
        pango-devel \
        gdk-pixbuf2-devel \
        libsoup3-devel \
        xdg-utils \
        gstreamer1 \
        gstreamer1-plugins-base \
        gstreamer1-plugins-good \
        ImageMagick \
        desktop-file-utils \
        ShellCheck \
    && tdnf clean all

# Flatpak tooling lives in the builder so CI never apt-installs on Ubuntu.
# bubblewrap + ostree + fuse are required for flatpak-builder sandboxes.
RUN tdnf -y install \
        flatpak \
        flatpak-builder \
        ostree \
        bubblewrap \
        xdg-dbus-proxy \
        elfutils \
        fuse \
        fuse3 \
        appstream \
        libappstream-glib \
        cmake \
        ninja-build \
        intltool \
        gettext \
        autoconf \
        automake \
        libtool \
    && tdnf clean all

RUN tdnf -y install libayatana-appindicator-gtk3 || tdnf -y install libappindicator-gtk3 || true
RUN tdnf -y install compiler-rt lld llvm || true
RUN tdnf clean all || true

# AZL clang looks under <arch>-azurelinux-linux; Fedora gcc is
# <arch>-redhat-linux, with <arch> x86_64 or aarch64 per TARGETARCH.
RUN set -eu; \
    tp=x86_64; \
    if [ "${TARGETARCH:-amd64}" = "arm64" ]; then tp=aarch64; fi; \
    azl="/usr/lib/gcc/${tp}-azurelinux-linux"; \
    rh="/usr/lib/gcc/${tp}-redhat-linux"; \
    if [ -d "$rh" ]; then \
      ver="$(ls -1 "$rh" | head -n1)"; \
      mkdir -p "$azl/$ver"; \
      cp -a "$rh/$ver"/. "$azl/$ver"/; \
    fi; \
    echo 'int main(void){return 0;}' > /tmp/aot-link-check.c; \
    clang -fuse-ld=bfd -pie -o /tmp/aot-link-check /tmp/aot-link-check.c; \
    rm -f /tmp/aot-link-check /tmp/aot-link-check.c

# Side-load .NET 11 preview SDK (not on Microsoft yum for AZL4 yet).
# Tarball arch: x64 for amd64 images, arm64 for arm64 images.
RUN sa=x64; \
    if [ "${TARGETARCH:-amd64}" = "arm64" ]; then sa=arm64; fi; \
    curl -fsSL \
      "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_SDK_VERSION}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-${sa}.tar.gz" \
      -o /tmp/dotnet-sdk.tar.gz \
    && mkdir -p /usr/share/dotnet /etc/environment.d /etc/profile.d \
    && tar -xzf /tmp/dotnet-sdk.tar.gz -C /usr/share/dotnet \
    && ln -sfn /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && rm -f /tmp/dotnet-sdk.tar.gz \
    && printf 'DOTNET_ROOT=/usr/share/dotnet\n' > /etc/environment.d/dotnet.conf \
    && printf '%s\n' \
        'export DOTNET_ROOT=/usr/share/dotnet' \
        'case ":$PATH:" in *:/usr/share/dotnet:*) ;; *) PATH="/usr/share/dotnet:$PATH" ;; esac' \
        'export PATH' \
        > /etc/profile.d/dotnet.sh \
    && /usr/share/dotnet/dotnet --info

# Flathub remote only during image build (no bwrap needed). GNOME 50 Platform,
# Sdk, Locale, GL, and codecs are seeded in a privileged post-build step in
# builder-image.yml (and by scripts/seed-flatpak-runtimes.sh for local podman).
# Weekly image rebuild refreshes those runtimes so CI does not re-download ~2GB.
RUN mkdir -p /var/lib/flatpak-builder-user && \
    flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo && \
    flatpak --version && flatpak-builder --version

WORKDIR /src
CMD ["./scripts/build-all.sh"]
