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

        var app = new CopilotApplication(options);
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
    public string? OpenUri { get; init; }

    public static CliOptions Parse(string[] args)
    {
        var tray = false;
        var daemon = false;
        var toggle = false;
        var help = false;
        var version = false;
        var smoke = false;
        string? openUri = null;

        foreach (var arg in args)
        {
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
                default:
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
              --smoke-test        Create the UI, then exit (CI / container check)
              --version, -V       Print version and exit
              --help, -h          Show this help

            Notes:
              Default GNOME has no system tray. The app is a normal window there:
              close quits, autostart opens a window. --tray / close-to-tray only
              matter if the host actually exposes a StatusNotifier tray.
              On Wayland, bind a desktop shortcut to
              `copilot-desktop-gtk --toggle-windows` for reliable show/hide.
            """);
    }
}
