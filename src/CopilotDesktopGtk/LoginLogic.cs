namespace CopilotDesktopGtk;

/// <summary>
/// Federated identity detection. Organizational ADFS/WS-Fed, Google, Apple,
/// and GitHub handoffs must stay inside the WebView so cookies land in our
/// session.
/// </summary>
internal static class LoginLogic
{
    public static bool IsFederatedIdentityProviderLogin(string? rawUrl)
    {
        if (string.IsNullOrWhiteSpace(rawUrl))
        {
            return false;
        }

        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri))
        {
            return MicrosoftFederatedLoginRaw(rawUrl);
        }

        return MicrosoftFederatedLogin(uri)
               || MicrosoftGithubLogin(uri)
               || GoogleLogin(uri)
               || AppleLogin(uri)
               || IsCopilotProviderFlow(uri, ["google-oauth2", "google", "apple", "github"]);
    }

    private static bool IsCopilotAuthCallbackUrl(string? rawUrl)
    {
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri))
        {
            return false;
        }

        return uri.Host.Equals("auth.copilot.microsoft.com", StringComparison.OrdinalIgnoreCase)
               && uri.AbsolutePath.Equals("/login/callback", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsCopilotProviderFlow(Uri uri, string[] allowedConnections)
    {
        if (!uri.Host.Equals("auth.copilot.microsoft.com", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (uri.AbsolutePath.Equals("/login/callback", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (!uri.AbsolutePath.Equals("/authorize", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var connection = GetQuery(uri, "connection");
        return !string.IsNullOrEmpty(connection) &&
               allowedConnections.Any(c => c.Equals(connection, StringComparison.OrdinalIgnoreCase));
    }

    private static bool MicrosoftFederatedLogin(Uri uri)
    {
        try
        {
            var realm = GetQuery(uri, "wtrealm");
            var action = GetQuery(uri, "wa");
            const string microsoftRealm = "urn:federation:microsoftonline";

            if (uri.AbsolutePath.Contains("/adfs/ls", StringComparison.OrdinalIgnoreCase) &&
                string.Equals(action, "wsignin1.0", StringComparison.OrdinalIgnoreCase))
            {
                if (!string.IsNullOrEmpty(realm) &&
                    realm.Equals(microsoftRealm, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }

                var contextPayload = GetQuery(uri, "wctx") ?? string.Empty;
                if (contextPayload.Contains("urn:federation:MicrosoftOnline", StringComparison.OrdinalIgnoreCase) ||
                    contextPayload.Contains("urn%3Afederation%3AMicrosoftOnline", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return (realm ?? string.Empty).Equals(microsoftRealm, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return MicrosoftFederatedLoginRaw(uri.ToString());
        }
    }

    private static bool MicrosoftFederatedLoginRaw(string raw) =>
        raw.Contains("wtrealm=urn:federation:MicrosoftOnline", StringComparison.OrdinalIgnoreCase) ||
        raw.Contains("wtrealm=urn%3Afederation%3AMicrosoftOnline", StringComparison.OrdinalIgnoreCase) ||
        (raw.Contains("/adfs/ls", StringComparison.OrdinalIgnoreCase) &&
         raw.Contains("wa=wsignin1.0", StringComparison.OrdinalIgnoreCase) &&
         raw.Contains("MicrosoftOnline", StringComparison.OrdinalIgnoreCase));

    private static bool MicrosoftGithubLogin(Uri uri)
    {
        if (!uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        const string callback = "https://login.live.com/HandleGithubResponse.srf";
        if (uri.AbsolutePath.Equals("/login/oauth/authorize", StringComparison.OrdinalIgnoreCase))
        {
            var redirect = GetQuery(uri, "redirect_uri") ?? string.Empty;
            return redirect.Equals(callback, StringComparison.OrdinalIgnoreCase);
        }

        if (uri.AbsolutePath.Equals("/login", StringComparison.OrdinalIgnoreCase))
        {
            var returnTo = GetQuery(uri, "return_to") ?? string.Empty;
            if (string.IsNullOrEmpty(returnTo))
            {
                return false;
            }

            try
            {
                var nested = new Uri(uri, returnTo);
                if (nested.AbsolutePath.Equals("/login/oauth/authorize", StringComparison.OrdinalIgnoreCase))
                {
                    var redirect = GetQuery(nested, "redirect_uri") ?? string.Empty;
                    return redirect.Equals(callback, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch
            {
                return returnTo.Contains("HandleGithubResponse.srf", StringComparison.OrdinalIgnoreCase);
            }
        }

        return false;
    }

    private static bool GoogleLogin(Uri uri)
    {
        if (!uri.Host.Equals("accounts.google.com", StringComparison.OrdinalIgnoreCase) &&
            !uri.Host.EndsWith(".google.com", StringComparison.OrdinalIgnoreCase))
        {
            // Also allow Copilot broker start for Google.
            return IsCopilotProviderFlow(uri, ["google-oauth2", "google"]);
        }

        var redirect = GetQuery(uri, "redirect_uri") ?? GetQuery(uri, "continue") ?? string.Empty;
        return IsCopilotAuthCallbackUrl(redirect) ||
               redirect.Contains("auth.copilot.microsoft.com", StringComparison.OrdinalIgnoreCase) ||
               redirect.Contains("login.microsoftonline.com", StringComparison.OrdinalIgnoreCase) ||
               redirect.Contains("login.live.com", StringComparison.OrdinalIgnoreCase);
    }

    private static bool AppleLogin(Uri uri)
    {
        if (!uri.Host.Equals("appleid.apple.com", StringComparison.OrdinalIgnoreCase))
        {
            return IsCopilotProviderFlow(uri, ["apple"]);
        }

        var redirect = GetQuery(uri, "redirect_uri") ?? string.Empty;
        return IsCopilotAuthCallbackUrl(redirect) ||
               redirect.Contains("auth.copilot.microsoft.com", StringComparison.OrdinalIgnoreCase);
    }

    private static string? GetQuery(Uri uri, string key)
    {
        var q = uri.Query;
        if (string.IsNullOrEmpty(q))
        {
            return null;
        }

        var pairs = q.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries);
        foreach (var pair in pairs)
        {
            var parts = pair.Split('=', 2);
            if (parts.Length == 0)
            {
                continue;
            }

            if (Uri.UnescapeDataString(parts[0]).Equals(key, StringComparison.OrdinalIgnoreCase))
            {
                return parts.Length > 1 ? Uri.UnescapeDataString(parts[1]) : string.Empty;
            }
        }

        return null;
    }
}
