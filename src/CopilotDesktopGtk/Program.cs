using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace CopilotDesktopGtk;

[SupportedOSPlatform("linux")]
internal static class Program
{
    private static int Main(string[] args)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            Console.Error.WriteLine("copilot-desktop-gtk only runs on Linux.");
            return 1;
        }

        // Prefer Wayland when available; WebKit/GTK pick it up from GDK_BACKEND.
        // Do not force X11. PipeWire is used automatically by WebKit media.
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GDK_BACKEND")))
        {
            var wayland = Environment.GetEnvironmentVariable("WAYLAND_DISPLAY");
            if (!string.IsNullOrEmpty(wayland))
            {
                Environment.SetEnvironmentVariable("GDK_BACKEND", "wayland");
            }
        }

        // Persistent WebKit data under XDG. NetworkSession stores cookies,
        // localStorage, IndexedDB, and HTTP auth here so login survives relaunch.
        Directory.CreateDirectory(AppConstants.UserDataDir);
        Directory.CreateDirectory(Path.Combine(AppConstants.UserDataDir, "webkit"));
        Directory.CreateDirectory(Path.Combine(AppConstants.UserDataDir, "cache", "webkit"));
        // Keep process-local cache rooted under our data dir (Flatpak --persist covers it).
        Environment.SetEnvironmentVariable("XDG_CACHE_HOME",
            Path.Combine(AppConstants.UserDataDir, "cache"));
        Directory.CreateDirectory(Path.Combine(AppConstants.UserDataDir, "cache"));

        var options = CliOptions.Parse(args);
        if (options.ShowHelp)
        {
            CliOptions.PrintHelp();
            return 0;
        }

        if (options.ShowVersion)
        {
            Console.WriteLine(AppConstants.Version);
            return 0;
        }

        // Resolve RAM/GPU profile before WebKit init so compositing env applies.
        var profile = RuntimeProfile.Resolve(options);
        if (profile.WebKitDebug || profile.LowMemory)
        {
            Console.WriteLine($"copilot-desktop-gtk profile: {profile.Summary}");
        }

        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.DefaultThreadCurrentUICulture = CultureInfo.InvariantCulture;

        WebKit.Module.Initialize();
        Gtk.Module.Initialize();
        try
        {
            Adw.Module.Initialize();
            // Leave ColorScheme at the libadwaita default so we track the
            // desktop color-scheme (dark or light).
            // PreferDark is available if a host wants to force dark later.
            _ = Adw.StyleManager.GetDefault();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"adw init skipped: {ex.Message}");
        }

        var app = new CopilotApplication(options, profile);
        return app.Run(args);
    }
}

internal sealed class CliOptions
{
    public bool StartInTray { get; init; }
    public bool Daemon { get; init; }
    public bool ToggleWindows { get; init; }
    public bool ShowHelp { get; init; }
    public bool ShowVersion { get; init; }
    public bool SmokeTest { get; init; }
    public bool LowMemory { get; init; }
    public bool WebKitDebug { get; init; }
    /// <summary>always | never | auto, or null to use env / defaults.</summary>
    public string? HardwareAcceleration { get; init; }
    public string? OpenUri { get; init; }

    public static CliOptions Parse(string[] args)
    {
        var tray = false;
        var daemon = false;
        var toggle = false;
        var help = false;
        var version = false;
        var smoke = false;
        var lowMemory = false;
        var webkitDebug = false;
        string? ha = null;
        string? openUri = null;

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            switch (arg)
            {
                case "--tray":
                    tray = true;
                    break;
                case "--daemon":
                    daemon = true;
                    tray = true;
                    break;
                case "--toggle-windows":
                case "--toggle":
                    toggle = true;
                    break;
                case "--help":
                case "-h":
                    help = true;
                    break;
                case "--version":
                case "-V":
                    version = true;
                    break;
                case "--smoke-test":
                    smoke = true;
                    break;
                case "--low-memory":
                    lowMemory = true;
                    break;
                case "--webkit-debug":
                    webkitDebug = true;
                    break;
                case "--hardware-acceleration":
                    if (i + 1 < args.Length)
                    {
                        ha = args[++i];
                    }
                    break;
                default:
                    if (arg.StartsWith("--hardware-acceleration=", StringComparison.Ordinal))
                    {
                        ha = arg["--hardware-acceleration=".Length..];
                        break;
                    }

                    if (arg.StartsWith("copilotdesktop:", StringComparison.OrdinalIgnoreCase) ||
                        arg.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
                        arg.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
                    {
                        openUri = arg;
                    }
                    break;
            }
        }

        return new CliOptions
        {
            StartInTray = tray || daemon,
            Daemon = daemon,
            ToggleWindows = toggle,
            ShowHelp = help,
            ShowVersion = version,
            SmokeTest = smoke,
            LowMemory = lowMemory,
            WebKitDebug = webkitDebug,
            HardwareAcceleration = ha,
            OpenUri = openUri,
        };
    }

    public static void PrintHelp()
    {
        Console.WriteLine(
            """
            copilot-desktop-gtk - unofficial Microsoft Copilot desktop app (GTK4/WebKit)

            Usage:
              copilot-desktop-gtk [options] [uri]

            Options:
              --tray              Prefer start-hidden when a tray host exists (else window)
              --daemon            Long-running helper mode (same as --tray for this app)
              --toggle-windows    Toggle visibility of the running instance (second launch)
              --low-memory        Prefer lower WebKit RAM (HA off, smaller cache, no page cache)
              --hardware-acceleration always|never|auto
                                  GPU policy (default auto: never on small/low-RAM hosts)
              --webkit-debug      Print page console.* and profile line to stdout
              --smoke-test        Create the UI, then exit (CI / container check)
              --version, -V       Print version and exit
              --help, -h          Show this help

            Environment:
              COPILOT_LOW_MEMORY=1
              COPILOT_HARDWARE_ACCELERATION=always|never|auto
              COPILOT_WEBKIT_DEBUG=1
              COPILOT_DISABLE_COMPOSITING=1
              WEBKIT_DISABLE_COMPOSITING_MODE=1

            Notes:
              Default GNOME has no system tray. The app is a normal window there:
              close quits, autostart opens a window. --tray / close-to-tray only
              matter if the host actually exposes a StatusNotifier tray.
              On Wayland, bind a desktop shortcut to
              `copilot-desktop-gtk --toggle-windows` for reliable show/hide.
              Auto low-memory turns on when MemTotal is at most 6 GiB or
              MemAvailable is under 2 GiB (typical constrained VMs).
            """);
    }
}
