# copilot-desktop-gtk

Unofficial Linux desktop app for [Microsoft Copilot](https://copilot.microsoft.com).

.NET 11, GTK4, WebKitGTK, Flatpak.

Display name in GNOME is **Copilot**. This project is not affiliated with,
sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks
are trademarks of Microsoft.

## Install

Recommended path installs from the project
[GitHub Pages Flatpak repo](https://sirredbeard.github.io/copilot-desktop-gtk/)
and keeps that remote for updates:

```bash
flatpak install --user flathub org.gnome.Platform//50
flatpak install --user --from \
  https://sirredbeard.github.io/copilot-desktop-gtk/com.github.sirredbeard.copilot-desktop-gtk.flatpakref
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

Later:

```bash
flatpak update
```

Add the remote without installing:

```bash
flatpak remote-add --if-not-exists --user --no-gpg-verify \
  copilot-desktop-gtk \
  https://sirredbeard.github.io/copilot-desktop-gtk/copilot-desktop-gtk.flatpakrepo
flatpak install --user copilot-desktop-gtk \
  com.github.sirredbeard.copilot-desktop-gtk//stable
```

Single-file `.flatpak` bundles and a bare AOT binary are attached to
[GitHub Releases](https://github.com/sirredbeard/copilot-desktop-gtk/releases)
for offline/sideload. Bundles do not register the Pages remote; prefer the
`.flatpakref` when you want updates.

Repo landing page (human index):
https://sirredbeard.github.io/copilot-desktop-gtk/

## Build with Podman

Uses the project builder image (Azure Linux 4 + .NET 11 + Flatpak tooling).

```bash
# once: build the local builder image (or: ./scripts/podman-build-local.sh --pull-ghcr)
./scripts/build-builder-image.sh

# binary + icons + Flatpak + smoke (version from csproj unless you pass one)
./scripts/podman-build-local.sh
```

Artifacts land under `dist/publish/` and `dist/flatpak/`. After a local
Flatpak build you can stage a Pages-shaped tree with:

```bash
./scripts/stage-flatpak-pages.sh
```

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

MIT. See [LICENSE](LICENSE). Trademark and third-party notices are in
[NOTICE](NOTICE).
