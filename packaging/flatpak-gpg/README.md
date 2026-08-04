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

`scripts/build-flatpak.sh` signs **every** ostree ref tip with
`ostree gpg-sign` after `flatpak build-update-repo`, then refuses to
ship a Pages repo if any tip lacks `ostree.gpgsigs`. Summary is signed
via `flatpak build-update-repo --gpg-sign`.

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
