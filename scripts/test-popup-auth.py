#!/usr/bin/env python3
"""Check the source contract for OAuth popup handling.

This is intentionally a small source-level guard because the full GTK UI is
not available in every CI/build environment. The Native AOT build validates
the C# API usage; this test protects the behavior that matters for OAuth:
native window.open, related WebViews, and a closeable popup window.
"""
from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "src" / "CopilotDesktopGtk" / "MainWindow.cs"
SESSION = ROOT / "src" / "CopilotDesktopGtk" / "WebKitSession.cs"
PROGRAM = ROOT / "src" / "CopilotDesktopGtk" / "Program.cs"


def require(text: str, needle: str, path: Path) -> None:
    if needle not in text:
        raise SystemExit(f"popup-auth: missing {needle!r} in {path}")


def main() -> int:
    main_text = MAIN.read_text(encoding="utf-8")
    session_text = SESSION.read_text(encoding="utf-8")
    program_text = PROGRAM.read_text(encoding="utf-8")

    if "window.open = function" in main_text:
        raise SystemExit("popup-auth: window.open is still rewritten in-page")

    require(main_text, "return CreatePopupWebView(", MAIN)
    require(main_text, "allowAllPopups: _options.AllowPopups", MAIN)
    require(main_text, "private WebKit.WebView CreatePopupWebView", MAIN)
    require(main_text, "popupWebView.OnClose", MAIN)
    require(main_text, "popupWindow.OnCloseRequest", MAIN)
    require(main_text, "window.opener", MAIN)
    require(main_text, "IsPopupRequestAllowed", MAIN)
    require(main_text, "IsOAuthAuthorizationUri", MAIN)
    require(main_text, "AllowPopups", MAIN)
    require(main_text, "admittedAuthFlow", MAIN)
    require(main_text, "allowAllPopups", MAIN)
    require(main_text, "(!isNewWindow && IsInternalUri(uri))", MAIN)
    require(program_text, "COPILOT_ALLOW_POPUPS", PROGRAM)
    require(program_text, "--allow-popups", PROGRAM)
    require(session_text, '"related-view"', SESSION)
    require(session_text, "CreateRelatedWebView", SESSION)

    print("popup-auth: PASS (native related WebView flow is present)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
