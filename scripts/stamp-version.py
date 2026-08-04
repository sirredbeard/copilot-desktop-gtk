#!/usr/bin/env python3
"""Stamp X.Y.Z into AppConstants, csproj, and AppStream metainfo."""
from __future__ import annotations

import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        print("usage: stamp-version.py X.Y.Z", file=sys.stderr)
        return 2
    version = sys.argv[1]
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    root = Path(__file__).resolve().parent.parent

    app_cs = root / "src/CopilotDesktopGtk/AppConstants.cs"
    text = app_cs.read_text(encoding="utf-8")
    text2, n = re.subn(
        r'public const string Version = "\d+\.\d+\.\d+"',
        f'public const string Version = "{version}"',
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("AppConstants Version not updated")
    app_cs.write_text(text2, encoding="utf-8")

    csproj = root / "src/CopilotDesktopGtk/CopilotDesktopGtk.csproj"
    text = csproj.read_text(encoding="utf-8")
    text, n1 = re.subn(r"<Version>\d+\.\d+\.\d+</Version>", f"<Version>{version}</Version>", text, count=1)
    text, n2 = re.subn(
        r"<InformationalVersion>\d+\.\d+\.\d+</InformationalVersion>",
        f"<InformationalVersion>{version}</InformationalVersion>",
        text,
        count=1,
    )
    if n1 != 1 or n2 != 1:
        raise SystemExit("csproj Version not updated")
    csproj.write_text(text, encoding="utf-8")

    meta = root / "assets/metainfo/com.github.sirredbeard.copilot-desktop-gtk.metainfo.xml"
    text = meta.read_text(encoding="utf-8")
    text, n = re.subn(
        r'(<release version=")[^"]+(" date=")[^"]+(")',
        rf"\g<1>{version}\g<2>{date}\g<3>",
        text,
        count=1,
    )
    text, _ = re.subn(
        r"(releases/tag/v)\d+\.\d+\.\d+",
        rf"\g<1>{version}",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("metainfo release not updated")
    meta.write_text(text, encoding="utf-8")
    print(f"stamped {version} ({date})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
