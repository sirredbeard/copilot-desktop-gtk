# Copilot

<img src="assets/icons/copilot.png" width="128" alt="Copilot">

Unofficial Linux desktop app for [Microsoft Copilot](https://copilot.microsoft.com).

Native AOT .NET 11, GTK4, WebKitGTK. Shipped as Flatpak for x86_64 and aarch64.

* .NET: AOT, self-contained, speed-optimized
* GTK4 using [Gir.Core](https://github.com/gircore/gir.core)
* Flatpak on the latest [GNOME 50 Runtime](https://docs.flatpak.org/en/latest/available-runtimes.html) with [WebKitGTK](https://webkitgtk.org/)
* This repo is also a GPG-signed Flatpak repo on GitHub Pages. I wrote a [guide](https://github.com/sirredbeard/github-pages-flatpak-repo) on how to do this.
* [Automated builds](https://github.com/sirredbeard/copilot-desktop-gtk/blob/main/.github/workflows/release.yml) in GitHub Actions, from an Azure Linux [build container](https://github.com/sirredbeard/copilot-desktop-gtk/blob/main/container/Dockerfile)

This project is not affiliated with, sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks are trademarks of Microsoft.

<img width="1294" height="648" alt="01-desktop" src="https://github.com/user-attachments/assets/fdb38a9c-4a6d-4eaa-8d89-ec18fdb62dc5" />

<img width="1291" height="932" alt="Screenshot From 2026-08-06 19-32-15" src="https://github.com/user-attachments/assets/205b59ad-61fe-46b7-9604-b53e3eb9259b" />

## Install

x86_64:

```bash
flatpak install --user --from \
  https://sirredbeard.github.io/copilot-desktop-gtk/com.github.sirredbeard.copilot-desktop-gtk.flatpakref
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

aarch64:

```bash
flatpak install --user --from \
  https://sirredbeard.github.io/copilot-desktop-gtk/com.github.sirredbeard.copilot-desktop-gtk-aarch64.flatpakref
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

The `.flatpakref` adds the project repo for updates, embeds the signing key (`GPGKey=`), and pulls the GNOME runtime from Flathub when needed. Each arch has its own repo on the same Pages site: `repo/` for x86_64, `repo-aarch64/` for aarch64.

## Releases

[Releases](https://github.com/sirredbeard/copilot-desktop-gtk/releases) also have, per arch:

* A single-file `.flatpak` bundle (`-x86_64` / `-aarch64` in the file name)
* A bare Native AOT binary (no GNOME runtime), `copilot-desktop-gtk-x86_64` / `copilot-desktop-gtk-aarch64`

## Build with Podman

Uses the project builder image (Azure Linux 4, latest .NET 11 SDK, Flatpak tooling). The image is multi-arch: a local build builds the host arch, and CI builds each arch on a runner of that arch and joins them under one tag.

```bash
./scripts/build-builder-image.sh
./scripts/podman-build-local.sh
```

Or `./scripts/podman-build-local.sh --pull-ghcr` to skip the local image build.

Artifacts land under `dist/publish/` and `dist/flatpak/`.

Stage a Pages-shaped tree with `./scripts/stage-flatpak-pages.sh`. Local GPG signing is in [packaging/gpg/README.md](packaging/gpg/README.md).

## Build without Podman

Needs .NET 11 SDK, clang, gcc, and GTK4/WebKitGTK devel on the host.

```bash
./scripts/build-app.sh
./scripts/test-smoke.sh
./dist/publish/copilot-desktop-gtk
```

Flatpak on the host needs `flatpak`, `flatpak-builder` or `org.flatpak.Builder`, plus `org.gnome.Platform//50` and `org.gnome.Sdk//50`:

```bash
./scripts/build-icons.sh
./scripts/build-flatpak.sh
./scripts/stage-flatpak-pages.sh
```

## License

MIT. See [LICENSE](LICENSE). Trademark and third-party notices are in [NOTICE](NOTICE).
