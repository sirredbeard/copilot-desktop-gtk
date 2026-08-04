namespace CopilotDesktopGtk;

/// <summary>
/// Main application window: WebKit WebView pointed at copilot.microsoft.com,
/// navigation policy, offline banner (session-preserving), zoom, file chooser,
/// downloads, print, and media permissions (mic/camera/WebRTC).
/// </summary>
internal sealed class MainWindow : IDisposable
{
    private readonly Gtk.Application _app;
    private readonly CliOptions _options;
    private readonly RuntimeProfile _profile;
    private readonly WebKitSession _session;
    private readonly Action _onQuit;
    private readonly Gtk.ApplicationWindow _window;
    private readonly WebKit.WebView _webView;
    private readonly WebKit.Settings _webSettings;
    private bool _closeToTray;
    private bool _hasSuccessfulLoad;
    private bool _offlineBannerVisible;
    private bool _disposed;
    private double _zoom = 1.0;

    /// <param name="closeToTray">
    /// When true, window close hides to tray. When false (plain GNOME, no SNI
    /// host, missing library), close quits like a normal app.
    /// </param>
    public MainWindow(
        Gtk.Application app,
        CliOptions options,
        WebKitSession session,
        RuntimeProfile profile,
        bool closeToTray,
        Action onQuit)
    {
        _app = app;
        _options = options;
        _profile = profile;
        _session = session;
        _onQuit = onQuit;
        _closeToTray = closeToTray && !options.SmokeTest;

        _window = Gtk.ApplicationWindow.New(app);
        _window.Title = AppConstants.AppName;
        // Smaller default on low-RAM hosts reduces compositor/backing-store cost.
        if (profile.LowMemory)
        {
            _window.SetDefaultSize(960, 700);
        }
        else
        {
            _window.SetDefaultSize(1100, 800);
        }

        _window.Resizable = true;
        _window.HideOnClose = _closeToTray;

        // Close with no tray must tear the app down, not leave a headless process.
        _window.OnCloseRequest += (_, _) =>
        {
            if (_closeToTray)
            {
                HideWindow();
                return true;
            }

            _onQuit();
            return false;
        };

        try
        {
            _window.SetIconName("copilot-desktop-gtk");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"icon name skipped: {ex.Message}");
        }

        _webSettings = BuildWebSettings(profile);
        _webView = _session.CreateWebView();
        _webView.SetSettings(_webSettings);

        try
        {
            var ctx = WebKit.WebContext.GetDefault();
            ctx.SetCacheModel(profile.CacheModel);
            // Spellcheck dictionaries cost RAM; skip on constrained hosts.
            ctx.SetSpellCheckingEnabled(!profile.LowMemory);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"webkit context: {ex.Message}");
        }

        BuildChrome();
        WireWebViewSignals();
        WireDownloadHandling();
        WireShortcuts();

        _window.SetChild(_webView);
    }

    /// <summary>
    /// Tray host appeared/vanished mid-session (optional future use).
    /// </summary>
    public void SetCloseToTray(bool enabled)
    {
        _closeToTray = enabled && !_options.SmokeTest;
        _window.HideOnClose = _closeToTray;
    }

    public bool CloseToTray => _closeToTray;

    private void BuildChrome()
    {
        // Plain GNOME header: title only. Window controls already cover close;
        // no hamburger (About/autostart/quit duplicates).
        try
        {
            var header = Gtk.HeaderBar.New();
            header.TitleWidget = Gtk.Label.New(AppConstants.AppName);
            _window.SetTitlebar(header);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"header bar: {ex.Message}");
        }
    }

    private static WebKit.Settings BuildWebSettings(RuntimeProfile profile)
    {
        var s = WebKit.Settings.New();
        s.EnableJavascript = true;
        s.EnableJavascriptMarkup = true;
        s.EnableWebaudio = true;
        s.EnableMedia = true;
        s.EnableMediaStream = true;
        s.EnableMediaCapabilities = true;
        s.EnableMediasource = true;
        s.EnableEncryptedMedia = true;
        s.EnableWebrtc = true;
        s.EnableWebgl = profile.EnableWebgl;
        s.Enable2dCanvasAcceleration = profile.Enable2dCanvasAcceleration;
        s.EnableHtml5LocalStorage = true;
        s.EnableHtml5Database = true;
        // Back-forward page cache keeps whole page snapshots in RAM.
        s.EnablePageCache = profile.EnablePageCache;
        s.EnableSmoothScrolling = profile.EnableSmoothScrolling;
        s.EnableFullscreen = true;
        s.EnableSiteSpecificQuirks = true;
        s.EnableDeveloperExtras = false;
        // MS login (KMSI "Stay signed in") needs popups and a Chromium-class UA.
        // Safari-on-Linux UA leaves the Yes button disabled/stuck on WebKitGTK.
        s.JavascriptCanOpenWindowsAutomatically = true;
        s.JavascriptCanAccessClipboard = true;
        s.MediaPlaybackAllowsInline = true;
        s.MediaPlaybackRequiresUserGesture = false;
        // WebKitGTK 6 only exposes Always/Never (OnDemand was removed).
        s.HardwareAccelerationPolicy = profile.HardwareAcceleration;
        s.DefaultCharset = "UTF-8";
        // Page console.* is noisy (Clarity / CSP). Only mirror when debugging.
        try { s.EnableWriteConsoleMessagesToStdout = profile.WebKitDebug; }
        catch { /* older WebKit */ }

        // Font stack Microsoft web UIs expect on Linux: prefer metrics-compatible
        // Liberation/Carlito when installed, then Noto, then generic families.
        // fontconfig + host/Flatpak fonts do the real resolution.
        s.DefaultFontFamily = "sans-serif";
        s.SansSerifFontFamily = "Liberation Sans, Carlito, Noto Sans, DejaVu Sans, sans-serif";
        s.SerifFontFamily = "Liberation Serif, Caladea, Noto Serif, DejaVu Serif, serif";
        s.MonospaceFontFamily = "Liberation Mono, Noto Sans Mono, DejaVu Sans Mono, monospace";
        s.PictographFontFamily = "Noto Color Emoji, Noto Emoji, emoji";
        s.DefaultFontSize = 16;
        s.DefaultMonospaceFontSize = 13;
        s.MinimumFontSize = 0;

        // Edge-on-Windows UA: MSA treats this as a fully supported desktop browser
        // for KMSI. Linux Chrome UA alone still left Yes grayed on WebKitGTK.
        s.UserAgent =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0";
        return s;
    }

    public void Initialize()
    {
        if (_options.SmokeTest)
        {
            _webView.LoadUri("about:blank");
            return;
        }

        LoadApp();
    }

    public bool IsVisible() => _window.GetVisible();

    public void Navigate(string uri)
    {
        if (uri.Equals(AppConstants.ToggleUri, StringComparison.OrdinalIgnoreCase) ||
            uri.StartsWith("copilotdesktop:toggle", StringComparison.OrdinalIgnoreCase))
        {
            ToggleVisibility();
            return;
        }

        if (uri.StartsWith("copilotdesktop:", StringComparison.OrdinalIgnoreCase))
        {
            LoadApp();
            return;
        }

        if (AppConstants.IsHttpUrl(uri, out var parsed) && parsed is not null &&
            (AppConstants.IsAllowedHost(parsed.Host) || LoginLogic.IsFederatedIdentityProviderLogin(uri)))
        {
            _webView.LoadUri(uri);
            return;
        }

        LoadApp();
    }

    public void PresentWindow()
    {
        _window.Present();
        _window.SetVisible(true);
    }

    public void HideWindow()
    {
        _window.SetVisible(false);
    }

    public void ToggleVisibility()
    {
        if (_window.GetVisible())
        {
            HideWindow();
        }
        else
        {
            PresentWindow();
        }
    }

    public void ShowAbout()
    {
        try
        {
            var about = Adw.AboutDialog.New();
            about.ApplicationName = AppConstants.AppTitle;
            about.Version = AppConstants.Version;
            about.DeveloperName = AppConstants.Author;
            about.Website = AppConstants.HomepageUrl;
            about.IssueUrl = AppConstants.BugsUrl;
            about.LicenseType = Gtk.License.MitX11;
            about.Comments = AppConstants.Description +
                "\n\nThis project is not affiliated with, sponsored, or endorsed by Microsoft." +
                "\nMicrosoft, Copilot, and related marks are trademarks of Microsoft.";
            about.ApplicationIcon = "copilot-desktop-gtk";
            about.Present(_window);
            return;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"adw about failed, falling back to gtk: {ex.Message}");
        }

        var dialog = Gtk.AboutDialog.New();
        dialog.ProgramName = AppConstants.AppTitle;
        dialog.Version = AppConstants.Version;
        dialog.Authors = [AppConstants.Author];
        dialog.Website = AppConstants.HomepageUrl;
        dialog.Comments = AppConstants.Description;
        dialog.LicenseType = Gtk.License.MitX11;
        dialog.TransientFor = _window;
        dialog.Modal = true;
        dialog.Present();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        try
        {
            // Give WebProcesses a clean teardown path (avoids noisy
            // "WebProcess didn't exit as expected" after force-quit under OOM).
            try { _webView.StopLoading(); } catch { /* ignore */ }
            try { _webView.LoadUri("about:blank"); } catch { /* ignore */ }
            _window.Destroy();
        }
        catch
        {
            // already disposed by gtk
        }
    }

    private void LoadApp()
    {
        _offlineBannerVisible = false;
        _webView.LoadUri(AppConstants.AppUrl);
    }

    private void WireShortcuts()
    {
        AddAction("reload", LoadApp, ["<Control>r"]);
        AddAction("zoom-in", () => AdjustZoom(0.1), ["<Control>plus", "<Control>equal"]);
        AddAction("zoom-out", () => AdjustZoom(-0.1), ["<Control>minus"]);
        AddAction("zoom-reset", () => SetZoom(1.0), ["<Control>0"]);
        // Alt+H still useful for tray hosts; no header menu entry.
        AddAction("show-hide", ToggleVisibility, ["<Alt>h"]);
        AddAction("quit", _onQuit, ["<Control>q"]);
    }

    private void AddAction(string name, Action handler, string[] accels)
    {
        var action = Gio.SimpleAction.New(name, null);
        action.OnActivate += (_, _) =>
        {
            try
            {
                handler();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"action {name}: {ex.Message}");
            }
        };
        _app.AddAction(action);
        _app.SetAccelsForAction($"app.{name}", accels);
    }

    private void AdjustZoom(double delta) => SetZoom(_zoom + delta);

    private void SetZoom(double value)
    {
        _zoom = Math.Clamp(value, 0.5, 3.0);
        _webView.SetZoomLevel(_zoom);
    }

    private void WireWebViewSignals()
    {
        // window.open / target=_blank: WebKit emits create-web-view. If nobody
        // returns a WebView and NEW_WINDOW_ACTION is allowed, the URI is handed
        // to the host default browser. Always keep first-party traffic here.
        _webView.OnCreate += (sender, signalArgs) =>
        {
            try
            {
                var uri = signalArgs.NavigationAction?.GetRequest()?.GetUri() ?? string.Empty;
                Console.WriteLine($"create-web-view: {uri}");
                if (string.IsNullOrEmpty(uri) ||
                    uri.StartsWith("about:", StringComparison.Ordinal) ||
                    uri.StartsWith("blob:", StringComparison.Ordinal) ||
                    uri.StartsWith("data:", StringComparison.Ordinal))
                {
                    // Related blank window (then navigates) - reuse this view.
                    return _webView;
                }

                if (IsInternalUri(uri))
                {
                    LoadInPlace(uri);
                    return _webView;
                }

                // True external: stay in-app. Never hand URIs to the host browser
                // (launch spam like copilot.fun). Drop the popup.
                Console.WriteLine($"blocked external (create): {uri}");
                return null!;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"create-web-view: {ex.Message}");
                return _webView;
            }
        };

        _webView.OnDecidePolicy += (_, signalArgs) =>
        {
            var decision = signalArgs.Decision;
            var type = signalArgs.DecisionType;

            if (type != WebKit.PolicyDecisionType.NewWindowAction &&
                type != WebKit.PolicyDecisionType.NavigationAction)
            {
                return false;
            }

            if (decision is not WebKit.NavigationPolicyDecision nav)
            {
                return false;
            }

            var uri = nav.GetNavigationAction()?.GetRequest()?.GetUri() ?? string.Empty;
            var isNewWindow = type == WebKit.PolicyDecisionType.NewWindowAction;

            if (uri.StartsWith("about:", StringComparison.Ordinal) ||
                uri.StartsWith("copilot-desktop-gtk:", StringComparison.Ordinal) ||
                uri.StartsWith("data:", StringComparison.Ordinal) ||
                uri.StartsWith("blob:", StringComparison.Ordinal))
            {
                decision.Use();
                return true;
            }

            // Never Use() a NEW_WINDOW_ACTION without owning create-web-view.
            // Ignore + load in place for first-party; xdg-open only for outsiders.
            HandleNavigationPolicy(uri, decision, isNewWindow);
            return true;
        };

        _webView.OnLoadChanged += (_, signalArgs) =>
        {
            if (signalArgs.LoadEvent == WebKit.LoadEvent.Finished)
            {
                var uri = _webView.GetUri() ?? string.Empty;
                if (!string.IsNullOrEmpty(uri) &&
                    !uri.StartsWith("about:", StringComparison.Ordinal) &&
                    !uri.StartsWith("copilot-desktop-gtk:", StringComparison.Ordinal))
                {
                    _hasSuccessfulLoad = true;
                    _offlineBannerVisible = false;
                }

                // Re-run KMSI unlock after the login document finishes painting.
                if (IsMicrosoftLoginUri(uri))
                {
                    InjectKmsiUnlock();
                }
            }
        };

        _webView.OnLoadFailed += (_, signalArgs) =>
        {
            var message = signalArgs.Error?.Message ?? string.Empty;
            Console.Error.WriteLine($"load-failed: {message} going_to={signalArgs.FailingUri}");

            if (_options.SmokeTest)
            {
                return false;
            }

            if (!IsNetworkFailure(message))
            {
                return false;
            }

            // PR #44: preserve session on transient outages. If we already had
            // a live page, keep it and inject a non-destructive banner instead
            // of navigating to a blank offline document (which wiped auth).
            if (_hasSuccessfulLoad)
            {
                ShowOfflineBanner();
                return true;
            }

            LoadOfflinePage();
            return true;
        };

        _webView.OnPermissionRequest += (_, signalArgs) =>
        {
            var request = signalArgs.Request;
            try
            {
                switch (request)
                {
                    // Mic + camera for voice/vision. WebRTC and EME for media.
                    case WebKit.UserMediaPermissionRequest:
                    case WebKit.MediaKeySystemPermissionRequest:
                    case WebKit.NotificationPermissionRequest:
                    case WebKit.DeviceInfoPermissionRequest:
                    case WebKit.ClipboardPermissionRequest:
                        request.Allow();
                        return true;
                    // Cross-site storage between login.live.com and other MS
                    // hosts. Denying this leaves KMSI Yes stuck grayed-out.
                    case WebKit.WebsiteDataAccessPermissionRequest:
                        request.Allow();
                        return true;
                    // Copilot does not need host geolocation; keep it off.
                    case WebKit.GeolocationPermissionRequest:
                        request.Deny();
                        return true;
                    default:
                        // Prefer allow for unknown WebKit permission types used
                        // by first-party auth (safer than a hard deny).
                        try { request.Allow(); } catch { try { request.Deny(); } catch { /* ignore */ } }
                        return true;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"permission request: {ex.Message}");
                try { request.Deny(); } catch { /* ignore */ }
                return true;
            }
        };

        _webView.OnQueryPermissionState += (_, signalArgs) =>
        {
            try
            {
                var name = signalArgs.Query.GetName() ?? string.Empty;
                // https://w3c.github.io/permissions/#permission-registry
                if (name is "notifications" or "clipboard-read" or "clipboard-write"
                    or "microphone" or "camera" or "display-capture")
                {
                    signalArgs.Query.Finish(WebKit.PermissionState.Granted);
                }
                else if (name is "geolocation")
                {
                    signalArgs.Query.Finish(WebKit.PermissionState.Denied);
                }
                else
                {
                    signalArgs.Query.Finish(WebKit.PermissionState.Prompt);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"permission state: {ex.Message}");
            }

            return true;
        };

        _webView.OnPrint += (_, signalArgs) =>
        {
            try
            {
                // Gtk print dialog (CUPS / portal under Flatpak).
                signalArgs.PrintOperation.RunDialog(_window);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"print: {ex.Message}");
            }

            return true;
        };

        _webView.OnShowNotification += (_, signalArgs) =>
        {
            try
            {
                var n = signalArgs.Notification;
                var title = n.GetTitle() ?? AppConstants.AppName;
                var body = n.GetBody() ?? string.Empty;
                var gn = Gio.Notification.New(title);
                gn.SetBody(body);
                gn.SetIcon(Gio.ThemedIcon.New("copilot-desktop-gtk"));
                _app.SendNotification("copilot-desktop-gtk", gn);
                n.Clicked();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"notification: {ex.Message}");
            }

            return true;
        };

        _webView.OnRunFileChooser += (_, signalArgs) =>
        {
            try
            {
                PresentFileChooser(signalArgs.Request);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"file chooser: {ex.Message}");
                try { signalArgs.Request.Cancel(); } catch { /* ignore */ }
            }

            return true;
        };

        var ucm = _webView.GetUserContentManager();
        ucm.RegisterScriptMessageHandler("copilotDesktop", null);
        ucm.OnScriptMessageReceived += (_, signalArgs) =>
        {
            var value = ExtractJsMessage(signalArgs);
            if (string.Equals(value, "retry", StringComparison.OrdinalIgnoreCase))
            {
                LoadApp();
            }
        };

        // Lightweight helpers on every page. Do NOT attach KMSI MutationObserver
        // / setInterval here - that used to run on copilot.microsoft.com for the
        // whole session and burned CPU on a busy SPA DOM.
        var pageScript =
            """
            window.copilotDesktop = {
              retry: function () {
                try {
                  window.webkit.messageHandlers.copilotDesktop.postMessage('retry');
                } catch (e) {}
              }
            };
            // Keep window.open in this WebView for product hops. Do not rewrite
            // window.open on Microsoft login hosts - KMSI and federated login
            // break when open() is replaced with location.assign.
            (function () {
              try {
                var host = (location && location.hostname) ? location.hostname : '';
                var loginHost = /(^|\.)(login\.live\.com|login\.microsoftonline\.com|login\.microsoft\.com|account\.live\.com|account\.microsoft\.com|aadcdn\.ms(auth|ftauth)\.net)$/i.test(host);
                if (loginHost) return;
                var nativeOpen = window.open;
                window.open = function (url, name, specs) {
                  if (url) {
                    try { window.location.assign(url); } catch (e) { window.location.href = url; }
                    return window;
                  }
                  try { return nativeOpen ? nativeOpen.call(window, url, name, specs) : window; } catch (e) { return window; }
                };
              } catch (e) {}
            })();
            """;

        ucm.AddScript(WebKit.UserScript.New(
            source: pageScript,
            injectedFrames: WebKit.UserContentInjectedFrames.AllFrames,
            injectionTime: WebKit.UserScriptInjectionTime.Start,
            allowList: null,
            blockList: null));

        // KMSI unlock only on MSA / Entra login hosts (URI allow-list).
        ucm.AddScript(WebKit.UserScript.New(
            source: KmsiUnlockScript,
            injectedFrames: WebKit.UserContentInjectedFrames.AllFrames,
            injectionTime: WebKit.UserScriptInjectionTime.Start,
            allowList: MicrosoftLoginScriptAllowList,
            blockList: null));
    }

    /// <summary>
    /// WebKit user-script allow-list patterns for KMSI / login-only injection.
    /// </summary>
    private static readonly string[] MicrosoftLoginScriptAllowList =
    [
        "https://login.live.com/*",
        "https://*.login.live.com/*",
        "https://login.microsoftonline.com/*",
        "https://*.login.microsoftonline.com/*",
        "https://login.microsoft.com/*",
        "https://*.login.microsoft.com/*",
        "https://account.live.com/*",
        "https://account.microsoft.com/*",
        "https://*.account.microsoft.com/*",
        "https://aadcdn.msauth.net/*",
        "https://*.aadcdn.msauth.net/*",
        "https://aadcdn.msftauth.net/*",
        "https://*.aadcdn.msftauth.net/*",
    ];

    /// <summary>
    /// login.live / login.microsoftonline KMSI and related auth hosts.
    /// </summary>
    private static bool IsMicrosoftLoginUri(string uri)
    {
        if (!Uri.TryCreate(uri, UriKind.Absolute, out var parsed))
        {
            return false;
        }

        var host = parsed.Host;
        return host.Equals("login.live.com", StringComparison.OrdinalIgnoreCase) ||
               host.EndsWith(".login.live.com", StringComparison.OrdinalIgnoreCase) ||
               host.Equals("login.microsoftonline.com", StringComparison.OrdinalIgnoreCase) ||
               host.EndsWith(".login.microsoftonline.com", StringComparison.OrdinalIgnoreCase) ||
               host.Equals("login.microsoft.com", StringComparison.OrdinalIgnoreCase) ||
               host.EndsWith(".login.microsoft.com", StringComparison.OrdinalIgnoreCase) ||
               host.Equals("account.live.com", StringComparison.OrdinalIgnoreCase) ||
               host.Equals("account.microsoft.com", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Shared KMSI unlock + force-complete body (user script + post-load inject).
    /// Our WebKit cookie jar already persists sessions across launches; KMSI Yes
    /// just extends MSA cookie lifetime. Force-completing unblocks WebKitGTK when
    /// Microsoft leaves Yes grayed after capability checks fail.
    /// </summary>
    private const string KmsiUnlockScript = """
        (function () {
          if (window.__copilotKmsiBooted) return;
          window.__copilotKmsiBooted = true;

          // Client Hints polyfill: MSA feature-detects Chromium UA-CH. WebKitGTK
          // has none, which correlates with a permanently disabled KMSI Yes.
          try {
            if (!navigator.userAgentData) {
              var brands = [
                { brand: 'Chromium', version: '131' },
                { brand: 'Microsoft Edge', version: '131' },
                { brand: 'Not_A Brand', version: '24' }
              ];
              var uad = {
                brands: brands,
                mobile: false,
                platform: 'Windows',
                getHighEntropyValues: function () {
                  return Promise.resolve({
                    brands: brands,
                    mobile: false,
                    platform: 'Windows',
                    platformVersion: '15.0.0',
                    architecture: 'x86',
                    bitness: '64',
                    model: '',
                    uaFullVersion: '131.0.0.0',
                    fullVersionList: brands
                  });
                },
                toJSON: function () { return { brands: brands, mobile: false, platform: 'Windows' }; }
              };
              try {
                Object.defineProperty(navigator, 'userAgentData', { configurable: true, get: function () { return uad; } });
              } catch (e) {
                try { navigator.userAgentData = uad; } catch (e2) {}
              }
            }
          } catch (e) {}

          function isKmsiHost() {
            try {
              var h = location.hostname || '';
              return /(^|\.)(login\.live\.com|login\.microsoftonline\.com|login\.microsoft\.com|account\.live\.com|account\.microsoft\.com)$/i.test(h)
                || location.protocol === 'file:'
                || h === '127.0.0.1' || h === 'localhost';
            } catch (e) { return false; }
          }

          function pageLooksLikeKmsi() {
            try {
              var t = (document.body && (document.body.innerText || document.body.textContent)) || '';
              return /Stay signed in\?/i.test(t) || /Keep me signed in/i.test(t);
            } catch (e) { return false; }
          }

          function textOf(el) {
            try {
              return ((el.innerText || el.textContent || el.value || el.getAttribute('aria-label') || '') + '').replace(/\s+/g, ' ').trim();
            } catch (e) { return ''; }
          }

          function unlockEl(el) {
            if (!el) return;
            try {
              try { el.disabled = false; } catch (e) {}
              if (el.removeAttribute) {
                el.removeAttribute('disabled');
                el.removeAttribute('aria-disabled');
                el.removeAttribute('inert');
              }
              if (el.setAttribute) el.setAttribute('aria-disabled', 'false');
              if (el.tabIndex < 0) el.tabIndex = 0;
              if (el.classList) {
                ['disabled', 'is-disabled', 'fui-Button--disabled', 'win-button-disabled'].forEach(function (c) {
                  try { el.classList.remove(c); } catch (e) {}
                });
              }
              if (el.style) {
                el.style.pointerEvents = 'auto';
                el.style.cursor = 'pointer';
                el.style.opacity = '1';
                el.style.filter = 'none';
              }
              var p = el.parentElement, depth = 0;
              while (p && depth < 10) {
                if (p.style && p.style.pointerEvents === 'none') p.style.pointerEvents = 'auto';
                if (p.removeAttribute) p.removeAttribute('inert');
                p = p.parentElement;
                depth++;
              }
            } catch (e) {}
          }

          function collectButtons(root, out) {
            if (!root || !root.querySelectorAll) return;
            var nodes = root.querySelectorAll(
              '#idSIButton9, #idBtn_Accept, #acceptButton, button, input[type=submit], input[type=button], [role=button], [data-testid]'
            );
            for (var i = 0; i < nodes.length; i++) out.push(nodes[i]);
            var all = root.querySelectorAll ? root.querySelectorAll('*') : [];
            for (var j = 0; j < all.length; j++) {
              if (all[j].shadowRoot) collectButtons(all[j].shadowRoot, out);
            }
          }

          function findYesNo() {
            var buttons = [];
            collectButtons(document, buttons);
            var yes = null, no = null;
            for (var i = 0; i < buttons.length; i++) {
              var t = textOf(buttons[i]);
              if (!yes && (/^yes$/i.test(t) || /^accept$/i.test(t) || buttons[i].id === 'idSIButton9' || buttons[i].id === 'idBtn_Accept')) yes = buttons[i];
              if (!no && (/^no$/i.test(t) || /^decline$/i.test(t) || buttons[i].id === 'idBtn_Back')) no = buttons[i];
            }
            return { yes: yes, no: no, all: buttons };
          }

          function fireClick(el) {
            if (!el) return false;
            unlockEl(el);
            try { el.focus(); } catch (e) {}
            var opts = { bubbles: true, cancelable: true, view: window, buttons: 1, composed: true };
            try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch (e) {}
            try { el.dispatchEvent(new MouseEvent('mousedown', opts)); } catch (e) {}
            try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch (e) {}
            try { el.dispatchEvent(new MouseEvent('mouseup', opts)); } catch (e) {}
            try { el.dispatchEvent(new MouseEvent('click', opts)); } catch (e) {}
            try { if (typeof el.click === 'function') el.click(); } catch (e) {}
            // React 17+ props on DOM nodes.
            try {
              var keys = Object.keys(el);
              for (var i = 0; i < keys.length; i++) {
                var k = keys[i];
                if (k.indexOf('__reactProps$') === 0 || k.indexOf('__reactEventHandlers$') === 0) {
                  var props = el[k];
                  if (props && typeof props.onClick === 'function') {
                    props.onClick({
                      preventDefault: function () {},
                      stopPropagation: function () {},
                      nativeEvent: new MouseEvent('click', opts),
                      target: el,
                      currentTarget: el,
                      type: 'click',
                      bubbles: true,
                      cancelable: true,
                      defaultPrevented: false,
                      isTrusted: true
                    });
                  }
                }
              }
            } catch (e) {}
            // Classic form post.
            try {
              var form = el.form || (el.closest && el.closest('form'));
              if (form) {
                var hidden = form.querySelector('input[name="kmsi"], input[name="Kmsi"], input[name="DontShowAgain"]');
                if (hidden) { try { hidden.value = 'true'; } catch (e) {} }
                if (typeof form.requestSubmit === 'function') form.requestSubmit(el);
                else form.submit();
              }
            } catch (e) {}
            return true;
          }

          function diagnose(pair) {
            // Quiet by default; enable with COPILOT_WEBKIT_DEBUG on the host.
            try {
              if (!window.__copilotKmsiVerbose) return;
              var info = (pair.all || []).slice(0, 12).map(function (b) {
                return {
                  tag: b.tagName,
                  id: b.id || '',
                  text: textOf(b).slice(0, 40),
                  disabled: !!b.disabled,
                  aria: b.getAttribute && b.getAttribute('aria-disabled'),
                  cls: (b.className && b.className.toString) ? b.className.toString().slice(0, 80) : ''
                };
              });
              console.log('copilot-kmsi', location.href, 'looks=' + pageLooksLikeKmsi(), info);
            } catch (e) {}
          }

          function tick() {
            if (!isKmsiHost()) return;
            if (!pageLooksLikeKmsi() && !document.getElementById('idSIButton9')) return;
            var pair = findYesNo();
            diagnose(pair);
            if (pair.yes) {
              unlockEl(pair.yes);
              // First try enabling for a real user click; after a short settle,
              // force-complete so WebKitGTK never traps the user on a gray Yes.
              if (!window.__copilotKmsiForceAt) {
                window.__copilotKmsiForceAt = Date.now() + 1200;
              }
              if (Date.now() >= window.__copilotKmsiForceAt && !window.__copilotKmsiForced) {
                window.__copilotKmsiForced = true;
                if (window.__copilotKmsiVerbose) console.log('copilot-kmsi force-click Yes');
                fireClick(pair.yes);
                // Retry a couple times if React re-disables.
                setTimeout(function () { fireClick(pair.yes); }, 400);
                setTimeout(function () { fireClick(pair.yes); }, 1200);
              }
            }
          }

          function scheduleTick() {
            if (window.__copilotKmsiTickQueued) return;
            window.__copilotKmsiTickQueued = true;
            setTimeout(function () {
              window.__copilotKmsiTickQueued = false;
              tick();
            }, 150);
          }

          try {
            // Only login hosts get this script (UserScript allow-list).
            tick();
            if (!window.__copilotKmsiUnlockTimer) {
              // 750ms is enough for KMSI; 400ms was needlessly hot.
              window.__copilotKmsiUnlockTimer = setInterval(tick, 750);
            }
            document.addEventListener('DOMContentLoaded', tick, true);
            window.addEventListener('load', tick, true);
            if (window.MutationObserver && !window.__copilotKmsiMo) {
              window.__copilotKmsiMo = new MutationObserver(scheduleTick);
              try {
                window.__copilotKmsiMo.observe(document.documentElement || document, {
                  childList: true, subtree: true, attributes: true,
                  attributeFilter: ['disabled', 'aria-disabled', 'class', 'style']
                });
              } catch (e) {}
            }
          } catch (e) {}
        })();
        """;

    private void InjectKmsiUnlock()
    {
        _ = _webView.EvaluateJavascriptAsync(KmsiUnlockScript);
    }

    private void ShowOfflineBanner()
    {
        if (_offlineBannerVisible)
        {
            return;
        }

        _offlineBannerVisible = true;
        // Non-destructive: keep DOM/session, overlay a banner.
        _ = _webView.EvaluateJavascriptAsync(
            """
            (function () {
              if (document.getElementById('copilot-desktop-gtk-offline')) return;
              var b = document.createElement('div');
              b.id = 'copilot-desktop-gtk-offline';
              b.setAttribute('role','status');
              b.style.cssText = 'position:fixed;z-index:2147483647;left:0;right:0;top:0;padding:10px 16px;background:#5b5fc7;color:#fff;font:600 14px system-ui,sans-serif;display:flex;gap:12px;align-items:center;justify-content:center';
              b.innerHTML = '<span>Network issue detected. Your session is still here.</span><button id="copilot-desktop-gtk-retry" style="border:0;border-radius:6px;padding:6px 12px;font:600 13px system-ui;cursor:pointer">Retry</button>';
              document.documentElement.appendChild(b);
              document.getElementById('copilot-desktop-gtk-retry').onclick = function () {
                try { window.copilotDesktop.retry(); } catch (e) { location.reload(); }
              };
            })();
            """);
    }

    private void LoadOfflinePage()
    {
        try
        {
            var html = ResourceLoader.LoadText("offline.html");
            _webView.LoadHtml(html, "copilot-desktop-gtk://offline");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"offline page load failed: {ex.Message}");
            _webView.LoadHtml(
                "<html><body><h1>Offline</h1><p>Cannot reach Copilot. Check your network.</p></body></html>",
                null);
        }
    }

    private static string ExtractJsMessage(WebKit.UserContentManager.ScriptMessageReceivedSignalArgs signalArgs)
    {
        try
        {
            return signalArgs.Value?.ToString() ?? string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private void HandleNavigationPolicy(string uri, WebKit.PolicyDecision decision, bool isNewWindow)
    {
        if (!AppConstants.IsHttpUrl(uri, out var parsed) || parsed is null)
        {
            decision.Ignore();
            return;
        }

        if (IsInternalUri(uri))
        {
            if (isNewWindow)
            {
                // Deny the popup; navigate this window instead.
                decision.Ignore();
                LoadInPlace(uri);
                return;
            }

            decision.Use();
            return;
        }

        // Block external navigations quietly. Do not xdg-open / UriLauncher -
        // Copilot's marketing hops (e.g. copilot.fun) were opening a second
        // browser window on every launch.
        Console.WriteLine($"blocked external: {uri}");
        decision.Ignore();
    }

    private static bool IsInternalUri(string uri)
    {
        if (!AppConstants.IsHttpUrl(uri, out var parsed) || parsed is null)
        {
            return false;
        }

        return AppConstants.IsAllowedHost(parsed.Host) ||
               LoginLogic.IsFederatedIdentityProviderLogin(uri);
    }

    private void LoadInPlace(string uri)
    {
        if (string.IsNullOrEmpty(uri))
        {
            return;
        }

        var current = _webView.GetUri() ?? string.Empty;
        if (!string.Equals(current, uri, StringComparison.Ordinal))
        {
            _webView.LoadUri(uri);
        }
    }

    private void WireDownloadHandling()
    {
        try
        {
            _session.NetworkSession.OnDownloadStarted += (_, signalArgs) =>
            {
                var download = signalArgs.Download;
                download.AllowOverwrite = true;
                download.OnDecideDestination += (sender, destArgs) =>
                {
                    try
                    {
                        var suggested = destArgs.SuggestedFilename;
                        if (string.IsNullOrWhiteSpace(suggested))
                        {
                            suggested = "download";
                        }

                        // Sanitize path separators from the remote name.
                        suggested = suggested.Replace('/', '_').Replace('\\', '_');
                        var destDir = AppConstants.DownloadDir;
                        Directory.CreateDirectory(destDir);
                        var dest = UniquePath(Path.Combine(destDir, suggested));
                        download.SetDestination(dest);
                        Console.WriteLine($"download -> {dest}");
                    }
                    catch (Exception ex)
                    {
                        Console.Error.WriteLine($"download dest: {ex.Message}");
                    }

                    return false;
                };
                download.OnFailed += (_, failArgs) =>
                {
                    Console.Error.WriteLine($"download failed: {failArgs.Error?.Message}");
                };
                download.OnFinished += (_, _) =>
                {
                    Console.WriteLine($"download finished: {download.GetDestination()}");
                };
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"download wire: {ex.Message}");
        }
    }

    private static string UniquePath(string path)
    {
        if (!File.Exists(path))
        {
            return path;
        }

        var dir = Path.GetDirectoryName(path) ?? ".";
        var name = Path.GetFileNameWithoutExtension(path);
        var ext = Path.GetExtension(path);
        for (var i = 1; i < 10_000; i++)
        {
            var candidate = Path.Combine(dir, $"{name} ({i}){ext}");
            if (!File.Exists(candidate))
            {
                return candidate;
            }
        }

        return path;
    }

    private void PresentFileChooser(WebKit.FileChooserRequest request)
    {
        // Gtk.FileDialog is portal-backed under Flatpak and modern GNOME.
        var dialog = Gtk.FileDialog.New();
        dialog.Title = "Choose file";
        dialog.Modal = true;

        var allowMultiple = false;
        try { allowMultiple = request.SelectMultiple; }
        catch { /* ignore */ }

        if (allowMultiple)
        {
            _ = OpenManyAsync(dialog, request);
        }
        else
        {
            _ = OpenOneAsync(dialog, request);
        }
    }

    private async Task OpenOneAsync(Gtk.FileDialog dialog, WebKit.FileChooserRequest request)
    {
        try
        {
            var file = await dialog.OpenAsync(_window);
            var path = file?.GetPath();
            if (string.IsNullOrEmpty(path))
            {
                request.Cancel();
                return;
            }

            request.SelectFiles([path]);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"file chooser: {ex.Message}");
            try { request.Cancel(); } catch { /* ignore */ }
        }
    }

    private async Task OpenManyAsync(Gtk.FileDialog dialog, WebKit.FileChooserRequest request)
    {
        try
        {
            var files = await dialog.OpenMultipleAsync(_window);
            if (files is null)
            {
                request.Cancel();
                return;
            }

            var paths = new List<string>();
            var n = files.GetNItems();
            for (uint i = 0; i < n; i++)
            {
                try
                {
                    // ListModel.GetItem returns a gpointer; wrap as Gio.File when possible.
                    var item = files.GetObject(i);
                    if (item is Gio.File gf)
                    {
                        var path = gf.GetPath();
                        if (!string.IsNullOrEmpty(path))
                        {
                            paths.Add(path);
                        }
                    }
                }
                catch
                {
                    // try next
                }
            }

            if (paths.Count == 0)
            {
                request.Cancel();
                return;
            }

            request.SelectFiles(paths.ToArray());
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"file chooser multi: {ex.Message}");
            try { request.Cancel(); } catch { /* ignore */ }
        }
    }

    private static bool IsNetworkFailure(string message)
    {
        var m = message.ToLowerInvariant();
        return m.Contains("network", StringComparison.Ordinal)
               || m.Contains("offline", StringComparison.Ordinal)
               || m.Contains("name or service not known", StringComparison.Ordinal)
               || m.Contains("temporary failure", StringComparison.Ordinal)
               || m.Contains("connection refused", StringComparison.Ordinal)
               || m.Contains("timed out", StringComparison.Ordinal)
               || m.Contains("unreachable", StringComparison.Ordinal)
               || m.Contains("dns", StringComparison.Ordinal)
               || m.Contains("tls", StringComparison.Ordinal)
               || m.Contains("ssl", StringComparison.Ordinal)
               || m.Contains("host not found", StringComparison.Ordinal);
    }
}
