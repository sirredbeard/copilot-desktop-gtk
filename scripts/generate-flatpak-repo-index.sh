#!/usr/bin/env bash
# generate-flatpak-repo-index.sh
#
# Purpose: Build simple HTML listings for a Pages-hosted Flatpak ostree repo.
#   GitHub Pages has no autoindex; without index.html directory URLs 404.
# Usage:   ./scripts/generate-flatpak-repo-index.sh SITE_DIR
# Expects: SITE_DIR/repo/ (ostree), optional .flatpakrepo / .flatpakref at SITE_DIR
# Env:     PAGES_OWNER, PAGES_REPO, FLATPAK_APP_ID, FLATPAK_APP_TITLE,
#          FLATPAK_BRANCH, FLATPAK_REMOTE_NAME
# CI:      Yes.

set -euo pipefail

SITE_DIR="${1:?usage: $0 SITE_DIR}"
REPO_DIR="$SITE_DIR/repo"
test -d "$REPO_DIR"

OWNER="${PAGES_OWNER:-USER}"
REPO_NAME="${PAGES_REPO:-REPO}"
APP_ID="${FLATPAK_APP_ID:-com.example.App}"
APP_TITLE="${FLATPAK_APP_TITLE:-Flatpak app}"
BRANCH="${FLATPAK_BRANCH:-stable}"
REMOTE_NAME="${FLATPAK_REMOTE_NAME:-$REPO_NAME}"
pages_root="https://${OWNER}.github.io/${REPO_NAME}/"
repo_url="${pages_root}repo/"
generated_at="$(date -u +'%Y-%m-%d %H:%M UTC')"

: > "$SITE_DIR/.nojekyll"
[[ -f "$REPO_DIR/manifest.txt" ]] || : > "$REPO_DIR/manifest.txt"

{
  cat <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${REPO_NAME} Flatpak repo</title>
<style>
  body { font-family: system-ui, sans-serif; line-height: 1.45; max-width: 52rem;
         margin: 1.5rem auto; padding: 0 1rem; }
  code { font-family: ui-monospace, monospace; font-size: 0.92em; }
  pre { background: #1112; padding: 0.75rem 1rem; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 0.75rem 0 1.25rem; }
  th, td { text-align: left; padding: 0.35rem 0.5rem; border-bottom: 1px solid #8884; }
  .muted { opacity: 0.8; font-size: 0.92rem; }
</style>
</head>
<body>
<h1>Flatpak repository</h1>
<p class="muted">Generated ${generated_at}. Base URL: <code>${repo_url}</code></p>
<p>
This tree is a normal Flatpak ostree repository hosted on GitHub Pages.
Browsers do not get automatic directory listings here, so this page is the human index.
Point a <code>.flatpakrepo</code> / <code>.flatpakref</code> at the site root, or add the remote by URL.
</p>
<h2>Install ${APP_TITLE}</h2>
<pre>flatpak install --user flathub org.gnome.Platform//50
flatpak install --user --from ${pages_root}${APP_ID}.flatpakref
flatpak run ${APP_ID}</pre>
<p class="muted">
The <code>.flatpakref</code> path adds this remote and installs the app so
<code>flatpak update</code> pulls later releases from Pages. Unsigned personal
stream: Flatpak may ask you to confirm a remote without GPG.
</p>
<h2>Quick links</h2>
<ul>
  <li><a href="../${APP_ID}.flatpakref"><code>${APP_ID}.flatpakref</code></a></li>
  <li><a href="../${REMOTE_NAME}.flatpakrepo"><code>${REMOTE_NAME}.flatpakrepo</code></a></li>
  <li><a href="manifest.txt"><code>manifest.txt</code></a></li>
  <li><a href="config"><code>config</code></a> (ostree)</li>
  <li><a href="../">Site root</a></li>
</ul>
<h2>Refs</h2>
<table>
<thead><tr><th>Path</th></tr></thead>
<tbody>
HTML
  if [[ -d "$REPO_DIR/refs" ]]; then
    while IFS= read -r -d '' f; do
      rel="${f#"$REPO_DIR"/}"
      printf '<tr><td><code>%s</code></td></tr>\n' "$rel"
    done < <(find "$REPO_DIR/refs" -type f -print0 2>/dev/null | sort -z)
  fi
  cat <<'HTML'
</tbody>
</table>
</body>
</html>
HTML
} > "$REPO_DIR/index.html"

cat > "$SITE_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${REPO_NAME}</title>
<style>
  body { font-family: system-ui, sans-serif; line-height: 1.45; max-width: 42rem;
         margin: 2rem auto; padding: 0 1rem; }
  code, pre { font-family: ui-monospace, monospace; font-size: 0.92em; }
  pre { background: #1112; padding: 0.75rem 1rem; overflow-x: auto; }
  .muted { opacity: 0.8; font-size: 0.92rem; }
</style>
</head>
<body>
<h1>${APP_TITLE}</h1>
<p>Unofficial Linux desktop app for Microsoft Copilot. Flatpak repository on GitHub Pages.</p>
<p class="muted">Not affiliated with, sponsored, or endorsed by Microsoft.</p>

<h2>Install (adds this repo for updates)</h2>
<pre>flatpak install --user flathub org.gnome.Platform//50
flatpak install --user --from ${pages_root}${APP_ID}.flatpakref
flatpak run ${APP_ID}</pre>

<h2>Add the remote only</h2>
<pre>flatpak remote-add --if-not-exists --user --no-gpg-verify \\
  ${REMOTE_NAME} ${pages_root}${REMOTE_NAME}.flatpakrepo
flatpak install --user ${REMOTE_NAME} ${APP_ID}//${BRANCH}
flatpak update</pre>

<h2>Links</h2>
<ul>
  <li><a href="${APP_ID}.flatpakref"><code>${APP_ID}.flatpakref</code></a></li>
  <li><a href="${REMOTE_NAME}.flatpakrepo"><code>${REMOTE_NAME}.flatpakrepo</code></a></li>
  <li><a href="repo/">Ostree repository (<code>repo/</code>)</a></li>
  <li><a href="https://github.com/${OWNER}/${REPO_NAME}">Source on GitHub</a></li>
  <li><a href="https://github.com/${OWNER}/${REPO_NAME}/releases">GitHub Releases</a> (single-file <code>.flatpak</code> bundles)</li>
</ul>
</body>
</html>
HTML

echo "Wrote indexes under $SITE_DIR"
