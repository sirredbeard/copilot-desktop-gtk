# Flatpak repo GPG signing

The GitHub Pages OSTree remote is GPG-signed so unprivileged
`flatpak update` and GNOME Software can pull system installs. Without
signatures, Flatpak refuses non-root system updates with:

`Can't pull from untrusted non-gpg verified remote`

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
