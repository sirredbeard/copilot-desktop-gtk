namespace CopilotDesktopGtk;

/// <summary>
/// Runtime knobs for WebKit cost vs fidelity. Auto low-memory kicks in on
/// small VMs or tight free RAM so the SPA is less likely to thrash the host.
/// Override with --low-memory / COPILOT_LOW_MEMORY or
/// --hardware-acceleration / COPILOT_HARDWARE_ACCELERATION.
/// </summary>
internal sealed class RuntimeProfile
{
    public bool LowMemory { get; init; }
    public bool WebKitDebug { get; init; }
    public WebKit.HardwareAccelerationPolicy HardwareAcceleration { get; init; }
    public WebKit.CacheModel CacheModel { get; init; }
    public bool EnablePageCache { get; init; }
    public bool EnableSmoothScrolling { get; init; }
    public bool Enable2dCanvasAcceleration { get; init; }
    public bool EnableWebgl { get; init; }
    public bool DisableCompositingEnv { get; init; }
    public string Summary { get; init; } = "";

    public static RuntimeProfile Resolve(CliOptions options)
    {
        var debug = options.WebKitDebug
                    || IsTruthy(Environment.GetEnvironmentVariable("COPILOT_WEBKIT_DEBUG"));

        var forceLow = options.LowMemory
                       || IsTruthy(Environment.GetEnvironmentVariable("COPILOT_LOW_MEMORY"));

        var (memTotalMb, memAvailMb) = ReadMemInfoMb();
        var autoLow = forceLow
                      || (memTotalMb > 0 && memTotalMb <= 6144)
                      || (memAvailMb > 0 && memAvailMb < 2048);

        var haEnv = options.HardwareAcceleration
                    ?? Environment.GetEnvironmentVariable("COPILOT_HARDWARE_ACCELERATION");
        var ha = ParseHa(haEnv, autoLow);

        // When HA is forced off or RAM is tight, also ask WebKit to skip the
        // compositing path (helps some VMs and software renderers).
        var disableCompositing = autoLow
                                 || ha == WebKit.HardwareAccelerationPolicy.Never
                                 || IsTruthy(Environment.GetEnvironmentVariable("COPILOT_DISABLE_COMPOSITING"));

        if (disableCompositing
            && string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WEBKIT_DISABLE_COMPOSITING_MODE")))
        {
            Environment.SetEnvironmentVariable("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
        }

        var profile = new RuntimeProfile
        {
            LowMemory = autoLow,
            WebKitDebug = debug,
            HardwareAcceleration = ha,
            CacheModel = autoLow ? WebKit.CacheModel.DocumentViewer : WebKit.CacheModel.WebBrowser,
            EnablePageCache = !autoLow,
            EnableSmoothScrolling = !autoLow,
            // Keep canvas/WebGL on unless very tight: Copilot UI uses canvas.
            // Low-memory still keeps them; Never HA is the main GPU/RAM lever.
            Enable2dCanvasAcceleration = true,
            EnableWebgl = true,
            DisableCompositingEnv = disableCompositing,
            Summary =
                $"low_memory={autoLow} ha={ha} cache={(autoLow ? "document-viewer" : "web-browser")} " +
                $"page_cache={!autoLow} compositing_off={disableCompositing} " +
                $"mem_total_mb={memTotalMb} mem_avail_mb={memAvailMb} debug={debug}",
        };

        return profile;
    }

    private static WebKit.HardwareAccelerationPolicy ParseHa(string? value, bool lowMemory)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            switch (value.Trim().ToLowerInvariant())
            {
                case "always":
                case "on":
                case "1":
                case "true":
                    return WebKit.HardwareAccelerationPolicy.Always;
                case "never":
                case "off":
                case "0":
                case "false":
                    return WebKit.HardwareAccelerationPolicy.Never;
                case "auto":
                    break;
            }
        }

        // WebKitGTK 6 only has Always/Never (OnDemand is gone). Prefer Always
        // on roomy hosts; Never on VMs / low free RAM to cut GPU process cost.
        return lowMemory
            ? WebKit.HardwareAccelerationPolicy.Never
            : WebKit.HardwareAccelerationPolicy.Always;
    }

    private static (long totalMb, long availMb) ReadMemInfoMb()
    {
        long total = 0, avail = 0;
        try
        {
            foreach (var line in File.ReadLines("/proc/meminfo"))
            {
                if (line.StartsWith("MemTotal:", StringComparison.Ordinal))
                {
                    total = ParseKb(line) / 1024;
                }
                else if (line.StartsWith("MemAvailable:", StringComparison.Ordinal))
                {
                    avail = ParseKb(line) / 1024;
                }
            }
        }
        catch
        {
            // non-Linux or restricted /proc
        }

        return (total, avail);
    }

    private static long ParseKb(string line)
    {
        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2 && long.TryParse(parts[1], out var kb) ? kb : 0;
    }

    private static bool IsTruthy(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return value is "1" or "true" or "TRUE" or "yes" or "YES" or "on" or "ON";
    }
}
