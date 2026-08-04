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
        'public const string Version = "%s"' % version,
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("AppConstants Version not updated")
    app_cs.write_text(text2, encoding="utf-8")

    csproj = root / "src/CopilotDesktopGtk/CopilotDesktopGtk.csproj"
    text = csproj.read_text(encoding="utf-8")
    text, n1 = re.subn(
        r"<Version>\d+\.\d+\.\d+</Version>",
        "<Version>%s</Version>" % version,
        text,
        count=1,
    )
    text, n2 = re.subn(
        r"<InformationalVersion>\d+\.\d+\.\d+</InformationalVersion>",
        "<InformationalVersion>%s</InformationalVersion>" % version,
        text,
        count=1,
    )
    if n1 != 1 or n2 != 1:
        raise SystemExit("csproj Version not updated")
    csproj.write_text(text, encoding="utf-8")

    meta_path = root / "assets/metainfo/com.github.sirredbeard.copilot-desktop-gtk.metainfo.xml"
    text = meta_path.read_text(encoding="utf-8")

    ver_re = re.compile(
        r'(<release\s+version="%s"[^>]*\bdate=")[^"]+(")' % re.escape(version)
    )
    if ver_re.search(text):
        text = ver_re.sub(r"\g<1>%s\g<2>" % date, text, count=1)
    else:
        block = (
            '    <release version="%s" date="%s" type="stable" urgency="medium">\n'
            '      <url type="details">https://github.com/sirredbeard/copilot-desktop-gtk/releases/tag/v%s</url>\n'
            "      <description>\n"
            "        <p>Copilot %s.</p>\n"
            "      </description>\n"
            "    </release>\n"
        ) % (version, date, version, version)
        text2, n = re.subn(r"(<releases>\s*)", r"\1" + block, text, count=1)
        if n != 1:
            raise SystemExit("metainfo <releases> not found")
        text = text2

    meta_path.write_text(text, encoding="utf-8")
    print("stamped %s (%s)" % (version, date))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
