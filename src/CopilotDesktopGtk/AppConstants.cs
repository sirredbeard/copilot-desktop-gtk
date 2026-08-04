namespace CopilotDesktopGtk;

/// <summary>
/// Shared constants for navigation policy and app identity.
/// Host allow-list for Copilot, Microsoft auth, federated IdPs
/// (Google/Apple/GitHub), and M365 cloud hosts.
/// </summary>
internal static class AppConstants
{
    public const string ApplicationId = "com.github.sirredbeard.copilot-desktop-gtk";
    public const string AppName = "Copilot Desktop";
    public const string AppTitle = "Copilot Desktop";
    public const string AppUrl = "https://copilot.microsoft.com/";
    public const string HomepageUrl = "https://github.com/sirredbeard/copilot-desktop-gtk";
    public const string BugsUrl = "https://github.com/sirredbeard/copilot-desktop-gtk/issues";
    public const string Author = "Hayden Barnes";
    public const string Description =
        "Unofficial desktop app for Microsoft Copilot on Linux.";
    public const string Version = "0.1.0";
    public const string ShowHideShortcutLabel = "Alt+H";
    public const string CustomScheme = "copilotdesktop";
    /// <summary>Open URI used to ferry --toggle-windows across single-instance.</summary>
    public const string ToggleUri = "copilotdesktop://toggle";

    public static readonly HashSet<string> AllowedHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        // Copilot product hosts (web app + short domain that often target=_blank)
        "copilot.microsoft.com",
        "www.copilot.microsoft.com",
        "auth.copilot.microsoft.com",
        "copilot.com",
        "www.copilot.com",
        // Microsoft first-party auth
        "login.microsoftonline.com",
        "login.live.com",
        "login.microsoft.com",
        "account.live.com",
        "account.microsoft.com",
        "www.microsoft.com",
        "microsoft.com",
        "aadcdn.msftauth.net",
        "aadcdn.msauth.net",
        "microsoftonline.com",
        // Federated IdPs used during Microsoft account login
        "accounts.google.com",
        "appleid.apple.com",
        "github.com",
        // M365 / Bing entry points the web app uses
        "copilot.cloud.microsoft",
        "m365.cloud.microsoft",
        "bing.com",
        "www.bing.com",
        "edgeservices.bing.com",
        "www.msn.com",
        "msn.com",
        "office.com",
        "www.office.com",
        "outlook.office.com",
        "outlook.live.com",
    };

    public static bool IsAllowedHost(string? host)
    {
        if (string.IsNullOrEmpty(host))
        {
            return false;
        }

        if (AllowedHosts.Contains(host))
        {
            return true;
        }

        foreach (var allowed in AllowedHosts)
        {
            if (host.EndsWith("." + allowed, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        // Broad Microsoft first-party suffixes. Prefer staying in-WebView over
        // dumping SSO/product hops into the default browser on launch.
        if (host.EndsWith(".microsoft.com", StringComparison.OrdinalIgnoreCase) ||
            host.Equals("microsoft.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".microsoftonline.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".microsoftonline-p.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".live.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".msn.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".bing.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".office.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".office.net", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".sharepoint.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".msauth.net", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".msftauth.net", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".msauthimages.net", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".msftauthimages.net", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".azureedge.net", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".microsoftpersonalcontent.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".copilot.cloud.microsoft", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".cloud.microsoft", StringComparison.OrdinalIgnoreCase) ||
            host.Equals("copilot.com", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".copilot.com", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }

    public static bool IsHttpUrl(string url, out Uri? uri)
    {
        uri = null;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed))
        {
            return false;
        }

        if (parsed.Scheme != Uri.UriSchemeHttp && parsed.Scheme != Uri.UriSchemeHttps)
        {
            return false;
        }

        uri = parsed;
        return true;
    }

    public static string UserDataDir
    {
        get
        {
            var xdg = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
            var root = string.IsNullOrEmpty(xdg)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "share")
                : xdg;
            return Path.Combine(root, "copilot-desktop-gtk");
        }
    }

    /// <summary>
    /// Where WebKit downloads land. Prefers XDG_DOWNLOAD_DIR, else ~/Downloads.
    /// </summary>
    public static string DownloadDir
    {
        get
        {
            var xdg = Environment.GetEnvironmentVariable("XDG_DOWNLOAD_DIR");
            if (!string.IsNullOrEmpty(xdg))
            {
                return Environment.ExpandEnvironmentVariables(xdg.Trim('"', '\''));
            }

            // user-dirs.dirs often sets this; fall back to ~/Downloads.
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return Path.Combine(home, "Downloads");
        }
    }
}
