# Copilot

Unofficial Linux desktop app for [Microsoft Copilot](https://copilot.microsoft.com).

<img width="1150" height="850" alt="Screenshot From 2026-08-04 04-45-27" src="https://github.com/user-attachments/assets/dc65f927-0c6d-4a34-afe6-49bb4934d29b" />

Built with the latest .NET 11 SDK, GTK4, and WebKitGTK, shipped via Flatpak.

This project is not affiliated with, sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks are trademarks of Microsoft.

## Install from GitHub

```bash
flatpak install --user --from \
  https://sirredbeard.github.io/copilot-desktop-gtk/com.github.sirredbeard.copilot-desktop-gtk.flatpakref
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

The `.flatpakref` adds the project remote for updates, embeds the Pages
signing key (`GPGKey=`), and pulls the GNOME runtime from Flathub when
needed.

System installs (for example a desktop image that puts the app under
`/var/lib/flatpak`) need that GPG path so non-root `flatpak update` and
GNOME Software can pull without root. Polkit still has to allow Deploy in
an active local session; GPG is the trust check, not a substitute for
polkit.

## Offline artifacts on GitHub Releases

[Releases](https://github.com/sirredbeard/copilot-desktop-gtk/releases) include:

* A single-file `.flatpak` bundle for side-loading
* A bare Native AOT binary

Prefer the `.flatpakref` when you want `flatpak update` from Pages. Bundles
are built with `flatpak build-bundle --repo-url=` pointing at the same
Pages ostree when possible.

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
