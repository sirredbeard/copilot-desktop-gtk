#!/usr/bin/env python3
"""Local WebKitGTK harness for KMSI Yes unlock/force-click script.

Loads a mock "Stay signed in?" page with a disabled Yes button, injects the
same logic we ship in MainWindow, and asserts Yes was clicked within a few
seconds. No network. No release dependency.
"""
from __future__ import annotations

import os
import sys
import tempfile

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("WebKit", "6.0")
from gi.repository import GLib, Gtk, WebKit  # noqa: E402

# Keep in sync with MainWindow.KmsiUnlockScript intent (force-click Yes).
SCRIPT = r"""
(function () {
  if (window.__copilotKmsiBooted) return;
  window.__copilotKmsiBooted = true;
  try {
    if (!navigator.userAgentData) {
      var brands = [
        { brand: 'Chromium', version: '131' },
        { brand: 'Microsoft Edge', version: '131' },
        { brand: 'Not_A Brand', version: '24' }
      ];
      var uad = {
        brands: brands, mobile: false, platform: 'Windows',
        getHighEntropyValues: function () {
          return Promise.resolve({ brands: brands, mobile: false, platform: 'Windows',
            platformVersion: '15.0.0', architecture: 'x86', bitness: '64', model: '',
            uaFullVersion: '131.0.0.0', fullVersionList: brands });
        }
      };
      try { Object.defineProperty(navigator, 'userAgentData', { configurable: true, get: function () { return uad; } }); }
      catch (e) { try { navigator.userAgentData = uad; } catch (e2) {} }
    }
  } catch (e) {}

  function pageLooksLikeKmsi() {
    try {
      var t = (document.body && (document.body.innerText || document.body.textContent)) || '';
      return /Stay signed in\?/i.test(t);
    } catch (e) { return false; }
  }
  function textOf(el) {
    return ((el.innerText || el.textContent || el.value || '') + '').replace(/\s+/g, ' ').trim();
  }
  function unlockEl(el) {
    if (!el) return;
    try { el.disabled = false; } catch (e) {}
    if (el.removeAttribute) { el.removeAttribute('disabled'); el.removeAttribute('aria-disabled'); }
    if (el.style) { el.style.pointerEvents = 'auto'; el.style.opacity = '1'; }
  }
  function findYes() {
    var nodes = document.querySelectorAll('button, input[type=submit], [role=button]');
    for (var i = 0; i < nodes.length; i++) {
      if (/^yes$/i.test(textOf(nodes[i])) || nodes[i].id === 'idSIButton9') return nodes[i];
    }
    return null;
  }
  function fireClick(el) {
    unlockEl(el);
    var opts = { bubbles: true, cancelable: true, view: window, buttons: 1 };
    try { el.dispatchEvent(new MouseEvent('click', opts)); } catch (e) {}
    try { el.click(); } catch (e) {}
  }
  function tick() {
    if (!pageLooksLikeKmsi()) return;
    var yes = findYes();
    if (!yes) return;
    unlockEl(yes);
    if (!window.__copilotKmsiForceAt) window.__copilotKmsiForceAt = Date.now() + 400;
    if (Date.now() >= window.__copilotKmsiForceAt && !window.__copilotKmsiForced) {
      window.__copilotKmsiForced = true;
      fireClick(yes);
    }
  }
  setInterval(tick, 200);
  tick();
})();
"""

HTML = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>KMSI mock</title></head>
<body style="background:#1b1b1b;color:#fff;font-family:sans-serif">
  <h1>Stay signed in?</h1>
  <p>Skip having to sign in every time.</p>
  <button id="yesBtn" disabled aria-disabled="true"
          style="opacity:.5;pointer-events:none">Yes</button>
  <button id="noBtn">No</button>
  <script>
    window.__yesClicked = false;
    document.getElementById('yesBtn').addEventListener('click', function () {
      window.__yesClicked = true;
      document.title = 'YES_CLICKED';
    });
  </script>
</body></html>
"""


def main() -> int:
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
            SCRIPT,
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
            return True  # keep polling until deadline

        GLib.timeout_add(200, check)

    view.connect("load-changed", on_load)

    def deadline():
        if not result["ok"]:
            # title fallback
            title = view.get_title() or ""
            if title == "YES_CLICKED":
                result["ok"] = True
                result["err"] = ""
            else:
                result["err"] = f"timeout title={title!r}"
        loop.quit()
        return False

    GLib.timeout_add(4000, deadline)
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
