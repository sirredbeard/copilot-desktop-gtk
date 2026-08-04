# copilot-desktop-gtk

Desktop app for [Microsoft Copilot](https://copilot.microsoft.com) for Linux.

Built with .NET 11, GTK4, and Flatpak.

This project is not affiliated with, sponsored, or endorsed by Microsoft. Microsoft, Copilot, and related marks are trademarks of Microsoft.

## Install

```bash
# needs org.gnome.Platform//50 from Flathub
flatpak install --user flathub org.gnome.Platform//50
flatpak install --user ./com.github.sirredbeard.copilot-desktop-gtk-0.1.0.flatpak
flatpak run com.github.sirredbeard.copilot-desktop-gtk
```

## Build with Podman

```bash
./scripts/build-builder-image.sh
./scripts/podman-build-local.sh 
./scripts/build-flatpak.sh
```

Artifacts:

- `dist/publish/copilot-desktop-gtk` - binary
- `dist/flatpak/*.flatpak` - single-file Flatpak bundle

## Build without Podman

Needs .NET 11 SDK, clang, gcc, and GTK4/WebKitGTK devel packages.

```bash
./scripts/build-app.sh
./scripts/test-smoke.sh
./dist/publish/copilot-desktop-gtk
```

## License

MIT. See [LICENSE](LICENSE) for the full text, trademark notice, and third-party component acknowledgements.
