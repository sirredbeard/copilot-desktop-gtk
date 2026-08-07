#!/usr/bin/env python3
"""Local WebKitGTK harness for KMSI Yes unlock/force-click script.

Loads a mock "Stay signed in?" page with a disabled Yes button + busy overlay,
injects MainWindow.KmsiUnlockScript from source, and asserts Yes was clicked.
No network. No release dependency.
"""
from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("WebKit", "6.0")
from gi.repository import GLib, Gtk, WebKit  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "src" / "CopilotDesktopGtk" / "MainWindow.cs"


def load_kmsi_script() -> str:
    text = MAIN.read_text(encoding="utf-8")
    match = re.search(
        r'private const string KmsiUnlockScript = """(.*?)""";',
        text,
        re.S,
    )
    if not match:
        raise SystemExit(f"KmsiUnlockScript not found in {MAIN}")
    return match.group(1)


HTML = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>KMSI mock</title></head>
<body style="background:#1b1b1b;color:#fff;font-family:sans-serif">
  <h1>Stay signed in?</h1>
  <p>Skip having to sign in every time.</p>
  <div class="ProgressRing" aria-busy="true"
       style="position:fixed;inset:0;pointer-events:auto;background:transparent"></div>
  <button id="idSIButton9" disabled aria-disabled="true"
          style="opacity:.5;pointer-events:none">Yes</button>
  <button id="idBtn_Back">No</button>
  <script>
    window.__yesClicked = false;
    document.getElementById('idSIButton9').addEventListener('click', function () {
      window.__yesClicked = true;
      document.title = 'YES_CLICKED';
    });
  </script>
</body></html>
"""


def main() -> int:
    script = load_kmsi_script()
    Gtk.init()
    loop = GLib.MainLoop()
    result = {"ok": False, "err": "timeout"}

    session = WebKit.NetworkSession.new_ephemeral()
    view = WebKit.WebView(network_session=session)
    settings = view.get_settings()
    settings.set_enable_write_console_messages_to_stdout(True)
    settings.set_user_agent(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
    )
    ucm = view.get_user_content_manager()
    ucm.add_script(
        WebKit.UserScript.new(
            "window.__copilotKmsiVerbose = true;\n" + script,
            WebKit.UserContentInjectedFrames.ALL_FRAMES,
            WebKit.UserScriptInjectionTime.START,
            None,
            None,
        )
    )

    win = Gtk.Window(title="kmsi-test")
    win.set_default_size(480, 360)
    win.set_child(view)

    fd, path = tempfile.mkstemp(suffix=".html")
    os.close(fd)
    with open(path, "w", encoding="utf-8") as f:
        f.write(HTML)
    uri = "file://" + path

    def on_load(view_obj, event):
        if event != WebKit.LoadEvent.FINISHED:
            return

        def check():
            title = view_obj.get_title() or ""
            if title == "YES_CLICKED":
                result["ok"] = True
                result["err"] = ""
                loop.quit()
                return False
            return True

        GLib.timeout_add(200, check)

    view.connect("load-changed", on_load)

    def deadline():
        if not result["ok"]:
            title = view.get_title() or ""
            if title == "YES_CLICKED":
                result["ok"] = True
                result["err"] = ""
            else:
                result["err"] = f"timeout title={title!r}"
        loop.quit()
        return False

    GLib.timeout_add(8000, deadline)
    view.load_uri(uri)
    win.present()
    loop.run()
    try:
        os.unlink(path)
    except OSError:
        pass

    if result["ok"]:
        print("kmsi-unlock: PASS (Yes force-clicked)")
        return 0
    print(f"kmsi-unlock: FAIL ({result['err']})", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
