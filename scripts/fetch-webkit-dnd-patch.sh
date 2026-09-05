#!/usr/bin/env bash
# fetch-webkit-dnd-patch.sh
#
# Purpose: Resolve both moving targets behind the WebKitGTK drag-and-drop
#          overlay (packaging/webkit-dnd/patch-source.json) - our fork's
#          fix branch HEAD, and upstream WebKit/WebKit's own main branch
#          HEAD - and, unless --sha-only is given, prepare a real git
#          working tree at upstream main with that one fix commit
#          cherry-picked on top. We deliberately do not backport onto
#          whatever older WebKitGTK release org.gnome.Platform//50 pins:
#          the fix was authored against a recent trunk state, so
#          cherry-picking it onto current upstream main is close to
#          conflict-free by construction, where rebasing onto a stable
#          release tag thousands of commits behind trunk is not (seen in
#          practice - multiple real content conflicts, not just line
#          offsets). This bundles a newer WebKit engine than GNOME's
#          runtime ships, built ourselves; see packaging/webkit-dnd/
#          README.md for the tradeoff. Nothing here is pinned to a fixed
#          commit - called fresh on every release so a push to either
#          moving target is picked up automatically.
# Usage:   ./scripts/fetch-webkit-dnd-patch.sh --sha-only
#            -> prints fork_head_sha=... and upstream_main_sha=... only
#               (cheap, two API calls, used by the no-VM check-version
#               job to build a cache key).
#          ./scripts/fetch-webkit-dnd-patch.sh <src_dir>
#            -> ensures <src_dir> is a git working tree checked out at
#               upstream main HEAD with the fork's fix commit
#               cherry-picked on top (staged, uncommitted), creating or
#               updating it in place so an unchanged pair of HEADs reuses
#               <src_dir> - and anything already built inside it - as-is.
#               Prints fork_head_sha=... and upstream_main_sha=... for
#               the caller to record what was actually used. Needs a real
#               git checkout, so this form only runs on the self-hosted
#               VM build step.
# Safety:  The cherry-pick uses -n (--no-commit), so the fix's own commit
#          message - which could reference the upstream bug/PR - is
#          staged into the working tree/index but never read into or
#          reproduced by any commit object, log, or output this script
#          produces. This repo intentionally does not hardcode any
#          upstream bug/PR identifier to grep for; doing that would
#          itself create the searchable cross-repo reference this
#          project must avoid.
# Needs:   --sha-only: curl + python3 only.
#          Full mode: git, curl, python3. An optional GH_TOKEN/GITHUB_TOKEN
#          env var is used if set, to raise the anonymous GitHub API rate
#          limit; both repos are public, so it isn't required to work.
# CI:      --sha-only: yes, cheap, safe on a plain GitHub-hosted step.
#          Full mode: self-hosted VM build step only (real git clones).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_SOURCE_JSON="${ROOT}/packaging/webkit-dnd/patch-source.json"

FORK_REPO="$(python3 -c "import json; print(json.load(open('${PATCH_SOURCE_JSON}'))['fork_repo'])")"
FORK_BRANCH="$(python3 -c "import json; print(json.load(open('${PATCH_SOURCE_JSON}'))['fork_branch'])")"
UPSTREAM_REPO="$(python3 -c "import json; print(json.load(open('${PATCH_SOURCE_JSON}'))['upstream_repo'])")"
UPSTREAM_REF="$(python3 -c "import json; print(json.load(open('${PATCH_SOURCE_JSON}'))['upstream_ref'])")"

AUTH_HEADER=()
if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    AUTH_HEADER=(-H "Authorization: ******")
fi

resolve_branch_head_sha() {
    local repo="$1" ref="$2"
    curl -fsSL "${AUTH_HEADER[@]}" \
        "https://api.github.com/repos/${repo}/commits/${ref}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])"
}

if [[ "${1:-}" == "--sha-only" ]]; then
    echo "fork_head_sha=$(resolve_branch_head_sha "$FORK_REPO" "$FORK_BRANCH")"
    echo "upstream_main_sha=$(resolve_branch_head_sha "$UPSTREAM_REPO" "$UPSTREAM_REF")"
    exit 0
fi

SRC_DIR="${1:?usage: fetch-webkit-dnd-patch.sh (--sha-only|<src_dir>)}"

FORK_HEAD_SHA="$(resolve_branch_head_sha "$FORK_REPO" "$FORK_BRANCH")"
UPSTREAM_MAIN_SHA="$(resolve_branch_head_sha "$UPSTREAM_REPO" "$UPSTREAM_REF")"

MARKER_FORK="${SRC_DIR}/.dnd-fork-head-sha"
MARKER_UPSTREAM="${SRC_DIR}/.dnd-upstream-main-sha"

if [[ -d "${SRC_DIR}/.git" && -f "$MARKER_FORK" && -f "$MARKER_UPSTREAM" \
        && "$(cat "$MARKER_FORK")" == "$FORK_HEAD_SHA" \
        && "$(cat "$MARKER_UPSTREAM")" == "$UPSTREAM_MAIN_SHA" ]]; then
    echo "=== Reusing existing patched source tree at ${SRC_DIR} (neither HEAD moved) ===" >&2
    echo "fork_head_sha=${FORK_HEAD_SHA}"
    echo "upstream_main_sha=${UPSTREAM_MAIN_SHA}"
    exit 0
fi

# Prefer an existing local bare mirror over a fresh network clone, if one
# is already sitting on this host for the exact same repo (shared cache
# convention already used on this VM by other WebKit build automation:
# /var/cache/webkit-dnd/mirrors/<name>.git or <name>-<owner>.git). A
# mirror is only trusted if its own origin remote matches the repo we
# actually want, so a filename coincidence can't silently pull the wrong
# history. Falls back to a plain network clone when no mirror is found or
# it doesn't have the ref we need yet.
MIRROR_DIR="${WEBKIT_DND_MIRROR_DIR:-/var/cache/webkit-dnd/mirrors}"

resolve_mirror_path() {
    local repo="$1" owner name candidate
    owner="${repo%%/*}"
    name="${repo##*/}"
    for candidate in "${MIRROR_DIR}/${name}.git" "${MIRROR_DIR}/${name}-${owner}.git"; do
        if [[ -d "$candidate" ]] && git -C "$candidate" remote get-url origin 2>/dev/null \
                | grep -qiF "github.com/${repo}"; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

set_remote_preferring_mirror() {
    local git_dir="$1" remote_name="$2" repo="$3" mirror
    if git --git-dir="$git_dir" remote get-url "$remote_name" >/dev/null 2>&1; then
        git --git-dir="$git_dir" remote remove "$remote_name"
    fi
    if mirror="$(resolve_mirror_path "$repo")"; then
        echo "=== Using existing local mirror for ${repo}: ${mirror} ===" >&2
        git --git-dir="$git_dir" remote add "$remote_name" "$mirror"
    else
        git --git-dir="$git_dir" remote add "$remote_name" "https://github.com/${repo}.git"
    fi
}

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    echo "=== No existing source tree at ${SRC_DIR} - creating one ===" >&2
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    git -C "$SRC_DIR" init -q
fi

set_remote_preferring_mirror "${SRC_DIR}/.git" upstream "$UPSTREAM_REPO"
set_remote_preferring_mirror "${SRC_DIR}/.git" fork "$FORK_REPO"

echo "=== Fetching upstream ${UPSTREAM_REPO}#${UPSTREAM_MAIN_SHA:0:12} ===" >&2
if ! git -C "$SRC_DIR" fetch -q --depth 1 upstream "$UPSTREAM_MAIN_SHA" 2>/dev/null; then
    mirror="$(resolve_mirror_path "$UPSTREAM_REPO")" || true
    if [[ -n "${mirror:-}" ]]; then
        echo "=== Local upstream mirror missing that commit - refreshing ${UPSTREAM_REF} from its origin ===" >&2
        git --git-dir="$mirror" fetch -q origin "${UPSTREAM_REF}:${UPSTREAM_REF}" || \
            git --git-dir="$mirror" fetch -q origin "$UPSTREAM_REF" || true
    fi
    git -C "$SRC_DIR" fetch -q --depth 1 upstream "$UPSTREAM_MAIN_SHA"
fi

echo "=== Fetching fork commit ${FORK_HEAD_SHA:0:12} + its parent (shallow) ===" >&2
if ! git -C "$SRC_DIR" fetch -q --depth 2 fork "$FORK_HEAD_SHA" 2>/dev/null; then
    mirror="$(resolve_mirror_path "$FORK_REPO")" || true
    if [[ -n "${mirror:-}" ]]; then
        echo "=== Local fork mirror missing the commit - refreshing ${FORK_BRANCH} from its origin ===" >&2
        git --git-dir="$mirror" fetch -q origin "${FORK_BRANCH}:${FORK_BRANCH}" || \
            git --git-dir="$mirror" fetch -q origin "$FORK_BRANCH" || true
    fi
    git -C "$SRC_DIR" fetch -q --depth 2 fork "$FORK_HEAD_SHA"
fi

# Discard any previous cherry-pick's staged-but-uncommitted state and any
# stray untracked files under version control's view, but never touch
# untracked build output (e.g. WebKitBuild/) sitting alongside it - only
# `git clean` inside directories git already tracks would do that, and we
# never pass -x/-d wide enough to reach a sibling build directory anyway
# as long as callers keep the build tree outside SRC_DIR's tracked paths.
git -C "$SRC_DIR" reset -q --hard "$UPSTREAM_MAIN_SHA"

echo "=== Cherry-picking ${FORK_HEAD_SHA:0:12} onto upstream ${UPSTREAM_REF}#${UPSTREAM_MAIN_SHA:0:12} ===" >&2
if ! git -C "$SRC_DIR" -c user.email="webkit-dnd-overlay@localhost" \
        -c user.name="webkit-dnd-overlay" \
        cherry-pick -n --keep-redundant-commits "$FORK_HEAD_SHA" 2>&1; then
    echo "error: cherry-pick of ${FORK_HEAD_SHA:0:12} onto upstream ${UPSTREAM_REF} conflicted." >&2
    echo "       The fix branch and upstream main have drifted apart; it needs a human" >&2
    echo "       to resolve (likely: rebase the fix branch onto current upstream main)." >&2
    git -C "$SRC_DIR" diff --stat >&2 || true
    git -C "$SRC_DIR" cherry-pick --abort 2>/dev/null || true
    exit 1
fi

if git -C "$SRC_DIR" diff --cached --quiet; then
    echo "error: cherry-pick produced no staged changes - something is wrong upstream." >&2
    exit 1
fi

echo "$FORK_HEAD_SHA" > "$MARKER_FORK"
echo "$UPSTREAM_MAIN_SHA" > "$MARKER_UPSTREAM"

echo "=== Prepared ${SRC_DIR}: upstream ${UPSTREAM_REF}#${UPSTREAM_MAIN_SHA:0:12} + fix ${FORK_HEAD_SHA:0:12} (staged) ===" >&2
echo "fork_head_sha=${FORK_HEAD_SHA}"
echo "upstream_main_sha=${UPSTREAM_MAIN_SHA}"
