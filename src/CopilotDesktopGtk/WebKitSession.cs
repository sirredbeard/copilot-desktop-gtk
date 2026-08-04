namespace CopilotDesktopGtk;

/// <summary>
/// Owns the persistent WebKit network session. Cookies, HTTP auth, localStorage,
/// IndexedDB, and cache all land under XDG data/cache so a signed-in Copilot
/// session survives process restarts. Ephemeral WebView.New() would wipe login
/// every launch; we never do that outside --smoke-test.
/// </summary>
internal sealed class WebKitSession : IDisposable
{
    private bool _disposed;

    public WebKit.NetworkSession NetworkSession { get; }
    public string DataDirectory { get; }
    public string CacheDirectory { get; }
    public string CookieDatabasePath { get; }

    private WebKitSession(WebKit.NetworkSession session, string dataDir, string cacheDir, string cookieDb)
    {
        NetworkSession = session;
        DataDirectory = dataDir;
        CacheDirectory = cacheDir;
        CookieDatabasePath = cookieDb;
    }

    public static WebKitSession Create(bool ephemeral)
    {
        var dataDir = Path.Combine(AppConstants.UserDataDir, "webkit");
        var cacheDir = Path.Combine(AppConstants.UserDataDir, "cache", "webkit");
        Directory.CreateDirectory(dataDir);
        Directory.CreateDirectory(cacheDir);

        if (ephemeral)
        {
            var ephemeralSession = WebKit.NetworkSession.NewEphemeral();
            return new WebKitSession(ephemeralSession, dataDir, cacheDir, string.Empty);
        }

        var session = WebKit.NetworkSession.New(dataDir, cacheDir);
        session.SetPersistentCredentialStorageEnabled(true);

        // ITP can break Microsoft multi-host SSO (login.live.com <-> copilot).
        // Keep third-party cookies available for the auth dance.
        try
        {
            session.SetItpEnabled(false);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"webkit itp: {ex.Message}");
        }

        var cookieDb = Path.Combine(dataDir, "cookies.sqlite");
        try
        {
            var cookies = session.GetCookieManager();
            // Always: federated login hops across several first-party sites.
            cookies.SetAcceptPolicy(WebKit.CookieAcceptPolicy.Always);
            cookies.SetPersistentStorage(cookieDb, WebKit.CookiePersistentStorage.Sqlite);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"webkit cookies: {ex.Message}");
        }

        return new WebKitSession(session, dataDir, cacheDir, cookieDb);
    }

    /// <summary>
    /// Build a WebView bound to this session so storage is shared and durable.
    /// </summary>
    public WebKit.WebView CreateWebView()
    {
        // network-session is construct-only on WebKitGTK 6.
        var view = WebKit.WebView.NewWithProperties(
        [
            new GObject.ConstructArgument(
                "network-session",
                new GObject.Value(NetworkSession)),
        ]);
        return view;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        // NetworkSession is a GObject; let GC/finalizer release the handle.
        // Explicit dispose of GObjects is not always safe mid-shutdown.
    }
}
