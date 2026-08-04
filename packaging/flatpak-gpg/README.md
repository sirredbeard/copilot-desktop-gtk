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

## Files in this directory (public only)

- `public.asc` - public key (committed; also served as
  `flatpak-signing-key.asc` on Pages)
- `keyid.txt` - short key id (committed)
- `public.b64` - optional one-line base64 of `public.asc` for `GPGKey=`

Private key material is **never** committed.

## GitHub Actions secrets (sirredbeard/copilot-desktop-gtk)

| Secret | Contents |
| --- | --- |
| `FLATPAK_GPG_PRIVATE_KEY` | Full armored private key (`BEGIN PGP PRIVATE KEY BLOCK`) |
| `FLATPAK_GPG_PUBLIC_KEY` | Full armored public key (`BEGIN PGP PUBLIC KEY BLOCK`) |
| `FLATPAK_GPG_KEY_ID` | Short key id (matches `keyid.txt`, e.g. `C997DB034A0C0179`) |

Release CI requires `FLATPAK_GPG_PRIVATE_KEY`. The public key and key id
are also stored as secrets so a future session can recover them without
hunting the working tree. GitHub does **not** let you download secret
values after they are set. To inspect or rotate:

```bash
# list names only (values are never shown)
gh secret list -R sirredbeard/copilot-desktop-gtk

# re-upload after export from a machine that still has the key
gh secret set FLATPAK_GPG_PRIVATE_KEY -R sirredbeard/copilot-desktop-gtk < private.asc
gh secret set FLATPAK_GPG_PUBLIC_KEY -R sirredbeard/copilot-desktop-gtk < packaging/flatpak-gpg/public.asc
gh secret set FLATPAK_GPG_KEY_ID -R sirredbeard/copilot-desktop-gtk -b "$(tr -d ' \n' < packaging/flatpak-gpg/keyid.txt)"
```

Public material is always recoverable from git (`public.asc`) or from
Pages:

`https://sirredbeard.github.io/copilot-desktop-gtk/flatpak-signing-key.asc`

If the private key is lost and not recoverable from a local backup, generate
a new key, replace `public.asc` / `keyid.txt`, update all three secrets, and
publish a new app release so clients pick up the new `GPGKey=`.

## Rotate

1. Generate a new key (`scripts/flatpak-gpg-import.sh --generate`).
2. Replace `public.asc` / `keyid.txt` (and `public.b64` if used).
3. Update the three GitHub Actions secrets above.
4. Publish a new app release so Pages commits are signed with the new key.
