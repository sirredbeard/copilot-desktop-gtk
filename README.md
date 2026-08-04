# copilot-desktop-gtk

Unofficial Linux desktop app for [Microsoft Copilot](https://copilot.microsoft.com).

.NET 11, GTK4, WebKitGTK, Flatpak.

Display name in GNOME is **Copilot**. This project is not affiliated with,
sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks
are trademarks of Microsoft.

## Install from GitHub

Use the project
[GitHub Pages Flatpak repo](https://sirredbeard.github.io/copilot-desktop-gtk/).
That path adds the `copilot-desktop-gtk` remote so later releases arrive with
`flatpak update` (and GNOME Software when that remote is configured).

```bash
flatpak install --user flathub org.gnome.Platform//50
flatpak install --user --from \
  https://sirredbeard.github.io/copilot-desktop-gtk/com.github.sirredbeard.copilot-desktop-gtk.flatpakref
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

Later:

```bash
flatpak update
# or: GNOME Software → Updates
```

Remote only:

```bash
flatpak remote-add --if-not-exists --user --no-gpg-verify \
  copilot-desktop-gtk \
  https://sirredbeard.github.io/copilot-desktop-gtk/copilot-desktop-gtk.flatpakrepo
flatpak install --user copilot-desktop-gtk \
  com.github.sirredbeard.copilot-desktop-gtk//stable
```

After a `.flatpakref` or remote install, `flatpak info` should show
`Origin: copilot-desktop-gtk` (not `sideload`).

Landing page: https://sirredbeard.github.io/copilot-desktop-gtk/

## Offline artifacts on GitHub Releases

[Releases](https://github.com/sirredbeard/copilot-desktop-gtk/releases) also
attach:

* A single-file `.flatpak` bundle (built with `--repo-url` pointing at the
  Pages ostree, so install can still register the update remote)
* A bare Native AOT binary (no Flatpak, no auto-updates)

Prefer the `.flatpakref` above when you are online. Opening an old `.flatpak`
in GNOME Software without a repo URL embedded shows **No Software Repository
Included** and will not update. If you already sideloaded that way, add the
remote (commands above) or reinstall from the `.flatpakref`.

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
