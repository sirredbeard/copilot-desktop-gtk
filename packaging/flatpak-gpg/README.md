# Flatpak repo GPG signing

The GitHub Pages OSTree remote is GPG-signed so unprivileged
`flatpak update` and GNOME Software can pull system installs. Without
signatures, Flatpak refuses non-root system updates with:

`Can't pull from untrusted non-gpg verified remote`

Polkit can authorize Deploy for wheel, but it cannot override Flatpak's
trust check for unsigned HTTPS system remotes. Per-commit GPG (or a
different install path such as `--user` or an RPM) is required for
system installs.

## What must be signed

`flatpak build-sign` alone only signs `app/*` commits. Clients also pull:

- `appstream2/x86_64` (GNOME Software catalog)
- `appstream/x86_64`
- `screenshots/x86_64`

Those tips need `ostree.gpgsigs` in `.commitmeta`. Missing signatures
show up as:

`GPG verification enabled, but no signatures found`

`scripts/build-flatpak.sh`:

1. Passes `--gpg-sign` to `flatpak-builder` when a key is available.
2. Refreshes appstream **without** static deltas.
3. Signs **every** ref tip with `ostree gpg-sign` (app, appstream,
   appstream2, screenshots).
4. **Then** generates static deltas + `summary.sig`.
5. Fails the build if any tip lacks `ostree.gpgsigs`, or if a local
   ostree pull that uses static deltas cannot verify the app or
   appstream2 tip.

Deltas before signatures is a hard fail for Flatpak clients: delta
pulls do not apply detached `.commitmeta`, so they report "no
signatures found" even when HTTP `.commitmeta` exists.

## Files

- `public.asc` — public key (committed)
- `keyid.txt` — short key id (committed)
- Private key is **not** in git. CI uses secret `FLATPAK_GPG_PRIVATE_KEY`
  (armored private key body). Local builds use
  `FLATPAK_GPG_HOME` or import the same armored key into a temp homedir.

## Rotate

1. Generate a new key (`scripts/flatpak-gpg-import.sh --generate`).
2. Replace `public.asc` / `keyid.txt`.
3. Update the GitHub Actions secret.
4. Publish a new app release so Pages commits are signed with the new key.
