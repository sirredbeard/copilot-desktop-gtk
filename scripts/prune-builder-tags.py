#!/usr/bin/env python3
"""Delete GHCR builder package versions that are not latest or YYYY.MM.DD."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

DATE_RE = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "-"
    if path == "-":
        data = json.load(sys.stdin)
    else:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    if not isinstance(data, list):
        data = [data]

    owner = os.environ.get("OWNER", "sirredbeard")
    pkg = os.environ.get("PKG", "copilot-desktop-gtk-builder")
    deleted = 0

    for version in data:
        tags = (version.get("metadata") or {}).get("container", {}).get("tags") or []
        vid = version.get("id")
        if not vid:
            continue
        if any(tag == "latest" or DATE_RE.match(tag) for tag in tags):
            print(f"keep {vid} tags={tags}")
            continue
        print(f"delete {vid} tags={tags}")
        ok = False
        for api_path in (
            f"users/{owner}/packages/container/{pkg}/versions/{vid}",
            f"orgs/{owner}/packages/container/{pkg}/versions/{vid}",
        ):
            result = subprocess.run(
                ["gh", "api", "-X", "DELETE", api_path],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode == 0:
                ok = True
                deleted += 1
                break
        if not ok:
            err = (result.stderr or result.stdout or "").strip()
            print(f"  delete failed for {vid}: {err}")

    print(f"pruned {deleted} legacy versions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
