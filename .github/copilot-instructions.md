# copilot-desktop-gtk - project instructions

Maintainer and coding-agent norms. User-facing install docs stay in `README.md`. Do not dump this level of detail into the README.

## What this is

Unofficial self-contained Native AOT .NET 11 GTK4/WebKit app for Microsoft Copilot on Linux x86_64. Display name is **Copilot Desktop**. Distribution is Flatpak-only (single-file bundle) plus a bare AOT binary on GitHub Releases.

Not affiliated with Microsoft. Trademark and third-party notices live in `LICENSE`.

## Non-negotiable norms

1. **Podman for local builds.** `./scripts/build-builder-image.sh` and `./scripts/podman-build-local.sh`. GHCR image: `ghcr.io/sirredbeard/copilot-desktop-gtk-builder`.
2. **Automate in GitHub Actions.** Weekly builder image + manual release dispatch. Prefer fixing Actions over "works on my machine."
3. **Builder image is the product build environment.** Azure Linux 4 base (`mcr.microsoft.com/azurelinux-beta/base/core:4.0`), Fedora 43 repos for GTK/WebKit/Flatpak tooling, side-loaded latest .NET 11 preview SDK. Flatpak tooling lives in the image. Release must not install Flatpak tooling on the Ubuntu runner; use the builder image. Rebuild weekly and on `container/**` changes. Local image builds use **podman**.
4. **Latest toolchains.** Newest .NET 11 preview/RC via `scripts/resolve-dotnet-sdk.sh`, newest GirCore that works, GNOME Flatpak runtime 50 (or current stable).
5. **.NET best practices.** `net11.0`, Native AOT (`PublishAot`), trimmed self-contained, `OptimizationPreference=Speed`, file-scoped namespaces, nullable enable. Prefer XDG paths. Binary should NEED only libc/libm; GTK/WebKit load at runtime from host or Flatpak runtime.
6. **Flatpak for the modern desktop path.** `org.gnome.Platform//50`, finish-args for Wayland, network, Pulse/PipeWire, devices (camera), CUPS, host fonts, portals, autostart, persist data dir. Single-file `.flatpak` bundle for Releases. Install LICENSE + complete AppStream metainfo so GNOME Software shows name, license, homepage, VCS, and release notes.
7. **GNOME-first. Tray is not a product feature.** Default GNOME (Fedora, Azure Linux with GNOME, etc.) has no system tray. Do not design around tray, do not bundle AppIndicator, do not center docs on tray. Autostart opens a normal window. Soft-load tray only if a host already has StatusNotifier + library; otherwise normal window and close quits.
8. **Login must persist.** `WebKit.NetworkSession` with on-disk cookies and website data under XDG. ITP off enough for MS SSO. Smoke tests may use ephemeral sessions.
9. **Stay inside the WebView for first-party traffic.** `NewWindowAction` must not `Use()` without a create-web-view handler (WebKitGTK will open the default browser). Load allowed hosts in the same window. Allow `copilot.com` / `www.copilot.com` and related Microsoft hosts. Only true external links go through `xdg-open`.
10. **Writing style.** Docs, comments, commit messages, workflow comments: plain voice. No em-dashes, no decorative emoji, no marketing filler. Spaced hyphen " - " if you need a dash. Precision and brevity over polish.
11. **Git authoring.** Never add `Co-authored-by`, Copilot trailers, or π signatures. Iterative commits on `main` are fine.
12. **README hygiene.** User-facing README stays short. Prefer plain lists over tables. Do not mention or compare to other third-party Copilot wrappers.
13. **Cancel noise.** Aggressively cancel and delete failed/spurious workflow runs after diagnosis. Get logs, fix, commit, re-run.

## Architecture (short)

- `Program.cs` - Gtk app id, Wayland preference, CLI
- `CopilotApplication.cs` - single-instance, optional tray Hold, Flatpak-aware autostart (windowed)
- `MainWindow.cs` - WebView, chrome, permissions, downloads, print, navigation policy
- `WebKitSession.cs` - persistent NetworkSession / cookies / website data
- `TrayIcon.cs` / `StatusNotifierHost.cs` - optional host tray only; not packaged
- `LoginLogic.cs` / `AppConstants.cs` - allow-listed hosts, URIs, identity strings ("Copilot Desktop")

## Builder image details

- Base: `mcr.microsoft.com/azurelinux-beta/base/core:4.0`
- GTK4 / WebKitGTK devel: Fedora 43 Everything + updates (`cost=50`)
- clang AOT link fix: copy Fedora `gcc` multilib into `x86_64-azurelinux-linux` triple
- .NET 11 SDK from release-metadata tarball → `/usr/share/dotnet`
- Flatpak stack in-image; `FLATPAK_USER_DIR=/var/lib/flatpak-builder-user`
- Pre-seeded Flathub install: `org.gnome.Platform//50`, `org.gnome.Sdk//50`, Locale for both, `org.freedesktop.Platform.GL.default//25.08` (+extra), `codecs-extra//25.08-extra` so release does not re-download ~2GB per run. Weekly builder rebuild refreshes them. `build-flatpak.sh` skips install when already present.
- Local tag `localhost/copilot-desktop-gtk-builder:latest`. GHCR: `latest` + `YYYY.MM.DD`. Registry `ghcr.io/sirredbeard/copilot-desktop-gtk-builder`
- Builder image seeds Flatpak runtimes in a privileged post-build container step (not via build-push-action inputs).
- GHCR builder tags: `latest` and `YYYY.MM.DD` (UTC build date) only. No sha/dotnet/commit tags.

Release runs **inside** that image with `--privileged` so bwrap works.

## Flatpak packaging

Prebuilt AOT binary only. Install:

- binary, `.desktop` files, icons under the app-id name
- metainfo with SPDX `MIT`, homepage / bugtracker / vcs-browser URLs, release description
- `LICENSE` under `/app/share/licenses/copilot-desktop-gtk/LICENSE`

Validate with `appstreamcli validate` when tooling is available. Prefer complete metainfo over GNOME Software placeholders.

## Scripts

- `resolve-app-version.sh` - read X.Y.Z from csproj / AppConstants (no hard-coded product version in scripts)
- `next-version.sh` - next patch from latest GitHub release tag; first release uses project version
- `stamp-version.py` / `stamp-version.sh` - write version into AppConstants/csproj/metainfo for release builds

- `seed-flatpak-runtimes.sh` - install GNOME 50 Platform/Sdk/GL/codecs into FLATPAK_USER_DIR

- `resolve-dotnet-sdk.sh` - latest .NET 11 SDK from release-metadata
- `build-builder-image.sh` - `podman build` local builder
- `podman-build-local.sh` - build/package/lint/smoke inside builder
- `build-app.sh` - Native AOT publish
- `build-icons.sh` - icon sizes from logo asset
- `build-flatpak.sh` - manifest → repo → single-file bundle
- `test-smoke.sh` - headless smoke of the AOT binary

## Workflows

- `builder-image.yml`: build + push builder to GHCR; weekly cron + path filters + manual dispatch. Tags: `latest` and `YYYY.MM.DD`.
- `release.yml`: manual dispatch only. Auto-bumps patch (0.1.0, 0.1.1, ...), builds AOT + Flatpak in the builder image, creates `vX.Y.Z` and a GitHub Release with binary + `.flatpak`. No separate CI workflow. No tag-push trigger.

Publish: `gh workflow run release.yml`

## Size and speed

- Prefer Speed optimization; keep publish trimmed + AOT.
- Do not ship a browser runtime; use WebKitGTK from the platform.
- Keep ILC GirCore array-marshaling warnings non-fatal unless they break a used API.

## What not to do

- Do not install Flatpak tooling on the Ubuntu Actions runner for the main build path; put it in the builder image.
- Do not require a GNOME tray extension or treat tray as default behavior.
- Do not wipe WebKit data between launches.
- Do not open the system browser for first-party Copilot/Microsoft hosts or for `NewWindowAction` on those hosts.
- Do not co-author commits or add tool signatures to git history.
