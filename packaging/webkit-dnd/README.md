# WebKitGTK drag-and-drop overlay (issue #2)

`org.gnome.Platform//50` ships WebKitGTK with `DataTransfer::allowsFileAccess()`
hard-disabled on every non-Cocoa port (the upstream fix for a real CVE). That
also kills legitimate external file drag-and-drop - dragging a file from
Nautilus into an upload area does nothing. We carry an out-of-tree fix on
our own WebKit fork that restores file access only for trusted drops
(external file managers, portal file lists), while keeping the CVE's actual
fix (page-authored `file://` strings can never become a filesystem grant).
See the fork branch itself for the design.

## Why a newer engine, not a backport

We build the overlay from upstream WebKit/WebKit's own `main` branch, with
our fork's fix commit cherry-picked on top - we do not backport the fix onto
whatever older WebKitGTK release `org.gnome.Platform//50` happens to pin.
The fix was authored against a recent trunk state, so cherry-picking it onto
current upstream main is close to conflict-free by construction. Rebasing it
onto a stable release tag that can be thousands of commits behind trunk is
not: tried in practice, it produced real content conflicts across several
files, not just line-offset noise, and would need manual conflict resolution
by hand on every drift between the fix branch and that release. Building
from upstream main avoids that entirely, at the cost of shipping a WebKit
engine that is newer than - and no longer identical to - the one GNOME's
runtime pins, so it does not inherit GNOME's own backports for anything
else in WebKitGTK past whatever main happens to include at build time.

## Why an overlay, not a runtime fork

We do not fork or replace `org.gnome.Platform//50`. The release still uses
the stock GNOME runtime as-is. Instead we build just the WebKitGTK shared
libraries and helper processes (`WebKitWebProcess`, `WebKitNetworkProcess`,
`WebKitGPUProcess`) from upstream WebKit main with our fix applied, and
install private copies of those into `/app` (the Canary pattern
flatpak-builder already documents). Everything else - GTK4, the rest of the
runtime - stays exactly what GNOME ships and updates.

## Both inputs move on their own schedule

Nothing here is pinned to a fixed commit:

- `scripts/fetch-webkit-dnd-patch.sh` reads `patch-source.json` and
  resolves both upstream WebKit/WebKit's `main` branch and our fork's fix
  branch to their *current* HEADs, every time it runs. There is no
  committed patch file and no stable tag to bump by hand - a new commit on
  either branch (e.g. addressing upstream review, or upstream WebKit
  landing new commits) is picked up on the next release automatically.

`.github/workflows/webkit-dnd-rebuild.yml` combines both signals into one
cache key. If neither moved since the last build, a release just reuses the
cached overlay in seconds and never starts the self-hosted build VM. If
either moved, the VM builds a fresh overlay (`scripts/build-patched-webkit.sh`)
and `scripts/stage-webkit-dnd-overlay.sh` stages it at
`dist/webkit-dnd-overlay/` for the `webkit-dnd-overlay` Flatpak module to
install.

## This repo never references the upstream WebKit bug/PR

`fetch-webkit-dnd-patch.sh` cherry-picks the fix commit with `git
cherry-pick -n` (`--no-commit`): the change is staged into the working
tree/index, but the original commit message - the only place a bug/PR
reference could come from - is never read into or reproduced by any commit
object, log, or other output this script produces. Nothing in this repo
hardcodes the upstream bug/PR identifiers for this fix; doing that as a
"safety" grep would itself create the searchable cross-repo reference that
must not exist here.

## Layout

- `patch-source.json` - fork repo/branch and upstream repo/ref to
  cherry-pick onto. The only thing to edit here is a rename of either
  branch; commit pinning is intentionally not tracked here.
- `../../scripts/fetch-webkit-dnd-patch.sh`
- `../../scripts/build-patched-webkit.sh`
- `../../scripts/stage-webkit-dnd-overlay.sh`
- `../../.github/workflows/webkit-dnd-rebuild.yml`
