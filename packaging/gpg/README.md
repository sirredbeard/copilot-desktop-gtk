# Project OpenPGP signing key

Shared signing key for this project's GitHub Pages Flatpak OSTree remote
(and the same material used for azurelinux-desktop kmod RPMs).

## Identity

- Name: Hayden Barnes (sirredbeard)
- Email: gpg@sirredbeard.github.io
- Key id: `8DA5774C35DA9BF9`
- Fingerprint: `09DCEFE2212F7881EE2058088DA5774C35DA9BF9`

## Files

- `public.asc` / `keyid.txt` - public (committed)
- Private key is not in git

## Actions secrets (`sirredbeard/copilot-desktop-gtk`)

| Secret | Contents |
| --- | --- |
| `GPG_PRIVATE_KEY` | Armored private key |
| `GPG_PUBLIC_KEY` | Armored public key |
| `GPG_KEY_ID` | Short key id |

`release.yml` requires `GPG_PRIVATE_KEY`. GitHub never returns secret
values after set.

```bash
gh secret list -R sirredbeard/copilot-desktop-gtk
gh secret set GPG_PRIVATE_KEY -R sirredbeard/copilot-desktop-gtk < private.asc
gh secret set GPG_PUBLIC_KEY -R sirredbeard/copilot-desktop-gtk < packaging/gpg/public.asc
gh secret set GPG_KEY_ID -R sirredbeard/copilot-desktop-gtk -b "$(tr -d ' \n' < packaging/gpg/keyid.txt)"
```

Public also on Pages as `signing-key.asc` and `flatpak-signing-key.asc`.

## Sign order (Flatpak)

Sign every OSTree tip (app + appstream2 + ...) **before** static deltas.
See `scripts/build-flatpak.sh`.
