# Copilot

**Unofficial** Linux desktop app for [Microsoft Copilot](https://copilot.microsoft.com).

Built with the latest .NET 11 SDK, GTK4, and WebKitGTK, shipped via Flatpak.

* .NET build: AOT, self-contained, speed-optimized build
* GTK4 using [Gir.Core](https://github.com/gircore/gir.core)
* Flatpak uses latest [GNOME 50 Runtime](https://docs.flatpak.org/en/latest/available-runtimes.html) with latest stable [WebKitGTK](https://webkitgtk.org/)
* This repo is also a Flatpak repo that provides updates for this app, implemented using GitHub Pages, GPG-signed (I wrote a [guide](https://github.com/sirredbeard/github-pages-flatpak-repo) on how to do this)
* Fully [automated builds](https://github.com/sirredbeard/copilot-desktop-gtk/blob/main/.github/workflows/release.yml) from GitHub Actions, built using an Azure Linux-based [build container](https://github.com/sirredbeard/copilot-desktop-gtk/blob/main/container/Dockerfile)

**This project is not affiliated with, sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks are trademarks of Microsoft.**

<img width="1294" height="648" alt="01-desktop" src="https://github.com/user-attachments/assets/fdb38a9c-4a6d-4eaa-8d89-ec18fdb62dc5" />

<img width="1291" height="932" alt="Screenshot From 2026-08-06 19-32-15" src="https://github.com/user-attachments/assets/205b59ad-61fe-46b7-9604-b53e3eb9259b" />

## Install from GitHub

```bash
flatpak install --user --from \
  https://sirredbeard.github.io/copilot-desktop-gtk/com.github.sirredbeard.copilot-desktop-gtk.flatpakref
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

The `.flatpakref` adds the project repo for updates to Flatpak, embeds the repo signing key (`GPGKey=`), and pulls the GNOME runtime from Flathub when needed.

## Offline artifacts on GitHub Releases

[Releases](https://github.com/sirredbeard/copilot-desktop-gtk/releases) include:

* A single-file `.flatpak` bundle for side-loading
* A bare Native AOT binary (does not use GNOME runtime)

## Build with Podman

Uses the project builder image (Azure Linux 4 + latest .NET 11 SDK + Flatpak tooling).

```bash
# once: build the local builder image (or: ./scripts/podman-build-local.sh --pull-ghcr)
./scripts/build-builder-image.sh

# binary + icons + Flatpak + smoke (version from csproj unless you pass one)
./scripts/podman-build-local.sh
```

Artifacts land under `dist/publish/` and `dist/flatpak/`.

After a local Flatpak build you can stage a Pages-shaped tree with:

```bash
./scripts/stage-flatpak-pages.sh
```

GPG signing for a local Pages tree: set `GPG_PRIVATE_KEY` or
`GPG_HOME`, run `./scripts/build-flatpak.sh` (signs every OSTree tip
before static deltas), then stage. See
[packaging/gpg/README.md](packaging/gpg/README.md).

## Build without Podman

Needs .NET 11 SDK, clang, gcc, and GTK4/WebKitGTK devel packages on the host.

```bash
./scripts/build-app.sh
./scripts/test-smoke.sh
./dist/publish/copilot-desktop-gtk
```

Flatpak on the host (needs `flatpak`, `flatpak-builder` or
`org.flatpak.Builder`, and `org.gnome.Platform//50` + `org.gnome.Sdk//50`):

```bash
./scripts/build-icons.sh
./scripts/build-flatpak.sh
./scripts/stage-flatpak-pages.sh
```

## License

MIT. See [LICENSE](LICENSE). Trademark and third-party notices are in [NOTICE](NOTICE).
