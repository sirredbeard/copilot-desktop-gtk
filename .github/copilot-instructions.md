# copilot-desktop-gtk - project instructions

Maintainer and coding-agent norms. User-facing install docs stay in `README.md`. Do not dump this level of detail into the README.

## What this is

Unofficial self-contained Native AOT .NET 11 GTK4/WebKit app for Microsoft Copilot on Linux x86_64. Display name is **Copilot** (not "Copilot Desktop"). Distribution is Flatpak from the GitHub Pages ostree repo (primary, with updates), plus single-file `.flatpak` and bare AOT binary on GitHub Releases.

Not affiliated with Microsoft. Trademark and third-party notices live in `LICENSE`.

## Non-negotiable norms

1. **Podman for local builds.** `./scripts/build-builder-image.sh` and `./scripts/podman-build-local.sh`. GHCR image: `ghcr.io/sirredbeard/copilot-desktop-gtk-builder`.
2. **Automate in GitHub Actions.** Weekly builder image + manual release dispatch. Prefer fixing Actions over "works on my machine."
3. **Builder image is the product build environment.** Azure Linux 4 base (`mcr.microsoft.com/azurelinux-beta/base/core:4.0`), Fedora 43 repos for GTK/WebKit/Flatpak tooling, side-loaded latest .NET 11 preview SDK. Flatpak tooling lives in the image. Release must not install Flatpak tooling on the Ubuntu runner; use the builder image. Rebuild weekly and on `container/**` changes. Local image builds use **podman**.
4. **Latest toolchains.** Newest .NET 11 preview/RC via `scripts/resolve-dotnet-sdk.sh`, newest GirCore that works, GNOME Flatpak runtime 50 (or current stable).
5. **.NET best practices.** `net11.0`, Native AOT (`PublishAot`), trimmed self-contained, `OptimizationPreference=Speed`, file-scoped namespaces, nullable enable. Prefer XDG paths. Binary should NEED only libc/libm; GTK/WebKit load at runtime from host or Flatpak runtime.
6. **Flatpak for the modern desktop path.** `org.gnome.Platform//50`, finish-args for Wayland, network, Pulse/PipeWire, Camera portal (no `--device=all`), CUPS, host fonts, XDG dirs for drag-drop, portals, autostart, persist data dir. No `org.freedesktop.secrets` or bare `org.freedesktop.DBus` talk-name. Single-file `.flatpak` bundle for Releases. Install LICENSE + complete AppStream metainfo so GNOME Software shows name, license, homepage, VCS, and release notes.
7. **GNOME-first. Tray is not a product feature.** Default GNOME (Fedora, Azure Linux with GNOME, etc.) has no system tray. Do not design around tray, do not bundle AppIndicator, do not center docs on tray. Autostart opens a normal window. Soft-load tray only if a host already has StatusNotifier + library; otherwise normal window and close quits.
8. **Login must persist.** `WebKit.NetworkSession` with on-disk cookies and website data under XDG. ITP off enough for MS SSO. Smoke tests may use ephemeral sessions.
9. **Stay inside the WebView for first-party traffic.** `NewWindowAction` must not `Use()` without a create-web-view handler (WebKitGTK will open the default browser). Load allowed hosts in the same window. Allow `copilot.com` / `www.copilot.com` and related Microsoft hosts. Block true external navigations and create-web-view requests (no host browser open).
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
- `LoginLogic.cs` / `AppConstants.cs` - allow-listed hosts, URIs, identity strings ("Copilot")

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

### GPG signing (Pages OSTree)

System HTTPS remotes need GPG for non-root updates and GNOME Software.
Polkit can authorize Deploy; it cannot replace Flatpak trust for unsigned
remotes (`Can't pull from untrusted non-gpg verified remote`).

Contract (`scripts/build-flatpak.sh` + `packaging/flatpak-gpg/`):

1. Import key from Actions secrets (see below) or local GPG home.
2. Refresh appstream **without** static deltas.
3. `ostree gpg-sign` **every** ref tip: `app/*`, `appstream2/x86_64`,
   `appstream/x86_64`, `screenshots/x86_64`. `flatpak build-sign` alone is
   not enough for Software (it signs app commits only).
4. **Then** `flatpak build-update-repo --generate-static-deltas`. Deltas
   built before signatures make default pulls report "no signatures found"
   even when HTTPS serves `.commitmeta` (delta path skips detached
   commitmeta). Object-only pulls with `--disable-static-deltas` hide this.
5. CI must prove a **default** (delta) pull of app + appstream2 before
   Pages deploy (`verify-pages-install` / local ostree pull without
   disabling deltas).
6. `stage-flatpak-pages.sh` embeds `GPGKey=` and ships
   `flatpak-signing-key.asc`.

Template twin for other apps:
[github-pages-flatpak-repo](https://github.com/sirredbeard/github-pages-flatpak-repo).


### Actions secrets (GPG key material)

UID: Hayden Barnes (sirredbeard) <gpg@sirredbeard.github.io>.
Key id `8DA5774C35DA9BF9`.

Repo secrets on `sirredbeard/copilot-desktop-gtk` (names only via
`gh secret list -R sirredbeard/copilot-desktop-gtk`):

- `GPG_PRIVATE_KEY` - armored private key; required by `release.yml`
- `GPG_PUBLIC_KEY` - armored public key (same body as
  `packaging/gpg/public.asc`)
- `GPG_KEY_ID` - short id (same as `packaging/gpg/keyid.txt`)

GitHub never returns secret values after set. Public key is also in git and
on Pages (`flatpak-signing-key.asc`). Keep a private offline backup outside
the repo; if the private key is gone, rotate (new key + commit public files +
re-set secrets + new release). Detail:
`packaging/gpg/README.md`.


Prebuilt AOT binary only. Install:

- binary, `.desktop` files, icons under the app-id name
- metainfo with SPDX `MIT`, homepage / bugtracker / vcs-browser URLs, release description
- `LICENSE` under `/app/share/licenses/copilot-desktop-gtk/LICENSE`

Validate with `appstreamcli validate` when tooling is available. Prefer complete metainfo over GNOME Software placeholders.

## Scripts

- `resolve-app-version.sh` - read X.Y.Z from csproj / AppConstants (no hard-coded product version in scripts)
- `next-version.sh` - next patch from latest GitHub release tag; first release uses project version
- `stamp-version.py` / `stamp-version.sh` - write version into AppConstants/csproj/metainfo for release builds
- `verify-flatpak-version.sh` - install bundle in temp FLATPAK_USER_DIR and assert Version/License
- `verify-flatpak-repo-install.sh` - post-Pages: install via remote/flatpakref (no bundle), assert origin + update path
- `stage-flatpak-pages.sh` - assemble Pages site from ostree repo + flatpakref/repo files (`GPGKey=` when public.asc present)
- `flatpak-gpg-import.sh` - import or generate signing key homedir
- GPG contract: `packaging/gpg/README.md` (sign all tips, then deltas)
- `generate-flatpak-repo-index.sh` - index.html + .nojekyll for Pages (no Jekyll, no bare dir 404s)

- `seed-flatpak-runtimes.sh` - install GNOME 50 Platform/Sdk/GL/codecs into FLATPAK_USER_DIR

- `resolve-dotnet-sdk.sh` - latest .NET 11 SDK from release-metadata
- `build-builder-image.sh` - `podman build` local builder
- `podman-build-local.sh` - build/package/lint/smoke inside builder
- `build-app.sh` - Native AOT publish
- `build-icons.sh` - icon sizes from logo asset
- `build-flatpak.sh` - manifest → ostree repo (stable branch); GPG-sign every tip; **then** static deltas; bundle
- `test-smoke.sh` - headless smoke of the AOT binary

## Workflows

- `builder-image.yml`: build + push builder to GHCR; weekly cron + path filters + manual dispatch. Tags: `latest` and `YYYY.MM.DD`.
- `release.yml`: manual dispatch only. Auto-bumps patch, builds AOT + Flatpak in the builder image, deploys Pages ostree repo, creates `vX.Y.Z` Release with binary + `.flatpak`. No separate CI workflow. No tag-push trigger.

Publish: `gh workflow run release.yml`

Release also stages `dist/pages-site` (ostree under `repo/`, `.flatpakrepo`,
`.flatpakref`, `index.html`, `.nojekyll`) and deploys it with
`actions/deploy-pages`. Landing URL:
`https://sirredbeard.github.io/copilot-desktop-gtk/`. Primary install path is the
`.flatpakref` so the Pages remote stays configured for `flatpak update`.
Bundles are built with `flatpak build-bundle --repo-url=` pointing at the same
Pages ostree so GNOME Software does not claim "No Software Repository Included"
when that metadata is present. Still document `.flatpakref` as the default.
Ostree repo is cached across runs (`flatpak-ostree-` cache key) for history/deltas.

Release versioning: `next-version.sh` picks the next patch, `stamp-version.sh` writes it into
AppConstants/csproj/metainfo, `build-flatpak.sh` stamps again before bundle export, and
`verify-flatpak-version.sh` fails the job unless `flatpak info` reports that Version and MIT.

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
- Do not generate static deltas before GPG-signing every OSTree tip (including appstream2).
- Do not treat `flatpak build-sign` alone or object-only ostree pulls as proof of a signed remote.
- Do not ship an unsigned Pages remote for system installs that GNOME Software should update.
