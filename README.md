# copilot-desktop-gtk

Desktop app for [Microsoft Copilot](https://copilot.microsoft.com) for Linux.

.NET 11, GTK4, and Flatpak.

This project is not affiliated with, sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks are trademarks of Microsoft.

## Install

```bash
flatpak install --user flathub org.gnome.Platform//50
flatpak install --user ./com.github.sirredbeard.copilot-desktop-gtk-*.flatpak
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

## Build with Podman

Uses the project builder image (Azure Linux 4 + .NET 11 + Flatpak tooling). Builds the Native AOT binary, icons, Flatpak bundle, and smoke-tests inside the container.

```bash
# once: build the local builder image (or: ./scripts/podman-build-local.sh --pull-ghcr)
./scripts/build-builder-image.sh

# binary + icons + Flatpak + smoke (version from csproj unless you pass one)
./scripts/podman-build-local.sh
```

Artifacts land under `dist/publish/` and `dist/flatpak/`.

Optional:

```bash
./scripts/podman-build-local.sh --pull-ghcr          # use ghcr.io builder
./scripts/podman-build-local.sh 1.2.3                # override bundle version
```

## Build without Podman

Needs .NET 11 SDK, clang, gcc, and GTK4/WebKitGTK devel packages on the host.

```bash
./scripts/build-app.sh
./scripts/test-smoke.sh
./dist/publish/copilot-desktop-gtk
```

Flatpak on the host (needs `flatpak`, `flatpak-builder` or `org.flatpak.Builder`, and `org.gnome.Platform//50` + `org.gnome.Sdk//50`):

```bash
./scripts/build-icons.sh
./scripts/build-flatpak.sh
```

## License

MIT. See [LICENSE](LICENSE). Trademark and third-party notices are in [NOTICE](NOTICE).
