# copilot-desktop-gtk-builder
#
# Azure Linux 4 base, Fedora 43 repos for GTK4/WebKit devel, side-loaded
# .NET 11 preview SDK, and Flatpak builder tooling. CI and local podman
# builds produce the Native AOT binary and the Flatpak bundle entirely
# inside this image. Rebuilt weekly via builder-image.yml.
#
# Build:  podman build -t copilot-desktop-gtk-builder -f container/Dockerfile .
# Run:    podman run --rm -v "$PWD":/src:Z copilot-desktop-gtk-builder ./scripts/build-all.sh

FROM mcr.microsoft.com/azurelinux-beta/base/core:4.0

ARG DOTNET_SDK_VERSION=11.0.100-preview.6.26359.118
ARG FEDORA_RELEASE=43

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
# treat [fedora43] as a Dockerfile instruction.
RUN printf '%s\n' \
      '[fedora43]' \
      'name=Fedora 43 Everything x86_64' \
      'baseurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/os/' \
      'enabled=1' \
      'gpgcheck=0' \
      'cost=50' \
      '' \
      '[fedora43-updates]' \
      'name=Fedora 43 Updates x86_64' \
      'baseurl=https://dl.fedoraproject.org/pub/fedora/linux/updates/43/Everything/x86_64/' \
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

# AZL clang looks under x86_64-azurelinux-linux; Fedora gcc is x86_64-redhat-linux.
RUN set -eu; \
    azl="/usr/lib/gcc/x86_64-azurelinux-linux"; \
    rh="/usr/lib/gcc/x86_64-redhat-linux"; \
    if [ -d "$rh" ]; then \
      ver="$(ls -1 "$rh" | head -n1)"; \
      mkdir -p "$azl/$ver"; \
      cp -a "$rh/$ver"/. "$azl/$ver"/; \
    fi; \
    echo 'int main(void){return 0;}' > /tmp/aot-link-check.c; \
    clang -fuse-ld=bfd -pie -o /tmp/aot-link-check /tmp/aot-link-check.c; \
    rm -f /tmp/aot-link-check /tmp/aot-link-check.c

# Side-load .NET 11 preview SDK (not on Microsoft yum for AZL4 yet).
RUN curl -fsSL \
      "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_SDK_VERSION}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-x64.tar.gz" \
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
