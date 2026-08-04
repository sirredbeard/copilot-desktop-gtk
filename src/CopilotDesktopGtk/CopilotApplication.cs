using System.Reflection;
using System.Text;

namespace CopilotDesktopGtk;

/// <summary>
/// Gio/Gtk application shell. Single-instance is free with ApplicationFlags.None
/// when the application id is set; a second launch activates the first and can
/// carry --toggle-windows via an Open URI to the primary instance.
/// </summary>
internal sealed class CopilotApplication
{
    private readonly CliOptions _options;
    private readonly Gtk.Application _app;
    private WebKitSession? _session;
    private MainWindow? _mainWindow;
    private TrayIcon? _tray;
    private bool _held;
    private bool _toggleOnActivate;

    public CopilotApplication(CliOptions options)
    {
        _options = options;
        _toggleOnActivate = options.ToggleWindows;
        _app = Gtk.Application.New(AppConstants.ApplicationId, Gio.ApplicationFlags.HandlesOpen);
        _app.OnActivate += OnActivate;
        _app.OnShutdown += OnShutdown;
        _app.OnOpen += OnOpen;
    }

    public int Run(string[] args)
    {
        // Strip our flags so GApplication does not treat them as files.
        // GApplication single-instance does not forward argv flags to the
        // primary process, so --toggle-windows is re-encoded as an Open URI
        // the primary handles in OnOpen.
        var forwarded = new List<string>();
        if (_options.ToggleWindows)
        {
            forwarded.Add(AppConstants.ToggleUri);
        }

        foreach (var a in args)
        {
            if (a is "--tray" or "--daemon" or "--toggle-windows" or "--toggle"
                or "--smoke-test" or "--help" or "-h" or "--version" or "-V")
            {
                continue;
            }

            if (a.StartsWith('-'))
            {
                continue;
            }

            forwarded.Add(a);
        }

        if (!string.IsNullOrEmpty(_options.OpenUri) &&
            !forwarded.Contains(_options.OpenUri, StringComparer.Ordinal))
        {
            forwarded.Add(_options.OpenUri!);
        }

        return _app.RunWithSynchronizationContext(forwarded.Count == 0 ? null : forwarded.ToArray());
    }

    private void OnOpen(Gio.Application sender, Gio.Application.OpenSignalArgs args)
    {
        // Custom scheme / URL open from desktop, plus toggle URI from a
        // second-instance --toggle-windows launch.
        EnsureWindow();
        var toggled = false;
        var navigated = false;
        try
        {
            var files = args.Files;
            if (files is not null)
            {
                foreach (var file in files)
                {
                    var uri = file.GetUri() ?? file.GetPath() ?? string.Empty;
                    if (string.IsNullOrEmpty(uri))
                    {
                        continue;
                    }

                    if (IsToggleUri(uri))
                    {
                        _mainWindow?.ToggleVisibility();
                        toggled = true;
                        continue;
                    }

                    _mainWindow?.Navigate(uri);
                    navigated = true;
                }
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"open handler: {ex.Message}");
        }

        // Toggle alone must not force a Present (hide would be undone).
        if (!toggled)
        {
            _mainWindow?.PresentWindow();
        }
        else if (navigated)
        {
            _mainWindow?.PresentWindow();
        }
    }

    private static bool IsToggleUri(string uri) =>
        uri.Equals(AppConstants.ToggleUri, StringComparison.OrdinalIgnoreCase) ||
        uri.Equals("copilotdesktop://toggle", StringComparison.OrdinalIgnoreCase) ||
        uri.StartsWith("copilotdesktop:toggle", StringComparison.OrdinalIgnoreCase);

    private void OnActivate(Gio.Application sender, EventArgs args)
    {
        if (_mainWindow is not null)
        {
            if (_toggleOnActivate)
            {
                // No tray: toggle still presents if somehow hidden.
                _mainWindow.ToggleVisibility();
                _toggleOnActivate = false;
                return;
            }

            _mainWindow.PresentWindow();
            return;
        }

        EnsureWindow();

        // --tray / --daemon: hide only when a real tray host is present.
        // Plain GNOME has no tray; hiding would leave a headless process.
        var startHidden = _options.StartInTray
                          && !_options.SmokeTest
                          && _tray is not null
                          && _mainWindow!.CloseToTray;

        if (startHidden)
        {
            _mainWindow!.HideWindow();
            Console.WriteLine("started in tray");
        }
        else
        {
            if (_options.StartInTray && _tray is null)
            {
                Console.WriteLine("no tray host; showing window instead of starting hidden");
            }

            _mainWindow!.PresentWindow();
            _toggleOnActivate = false;
        }

        if (!string.IsNullOrEmpty(_options.OpenUri))
        {
            _mainWindow.Navigate(_options.OpenUri!);
        }

        if (_options.SmokeTest)
        {
            GLib.Functions.TimeoutAdd(
                GLib.Constants.PRIORITY_DEFAULT,
                250,
                () =>
                {
                    Console.WriteLine("smoke-test: ok");
                    Quit();
                    return false;
                });
        }
    }

    private void EnsureWindow()
    {
        if (_mainWindow is not null)
        {
            return;
        }

        // Persistent network session keeps cookies/localStorage across launches.
        // Smoke tests use ephemeral storage so CI leaves no host residue.
        _session ??= WebKitSession.Create(ephemeral: _options.SmokeTest);

        var trayOk = false;
        if (!_options.SmokeTest)
        {
            // Library alone is not enough: stock GNOME has no SNI host.
            var hostPresent = StatusNotifierHost.IsAvailable();
            if (hostPresent)
            {
                _tray = TrayIcon.TryCreate(
                    onShowHide: () => _mainWindow!.ToggleVisibility(),
                    onAbout: () => _mainWindow!.ShowAbout(),
                    onQuit: Quit,
                    onAutostartChanged: enabled => Autostart.SetEnabled(enabled),
                    autostartEnabled: Autostart.IsEnabled());
                trayOk = _tray is not null;
            }
            else
            {
                Console.WriteLine(
                    "tray: no StatusNotifier host on the session bus " +
                    "(plain GNOME needs an AppIndicator extension); " +
                    "running as a normal windowed app");
            }
        }

        // Hold the application only when close-to-tray is active so hiding
        // the window does not exit. Without a tray, last-window-close exits.
        if (trayOk && !_held)
        {
            _app.Hold();
            _held = true;
        }

        _mainWindow = new MainWindow(
            _app,
            _options,
            _session,
            closeToTray: trayOk,
            onQuit: Quit);
        _mainWindow.Initialize();
    }

    private void OnShutdown(Gio.Application sender, EventArgs args)
    {
        _tray?.Dispose();
        _tray = null;
        _mainWindow?.Dispose();
        _mainWindow = null;
        _session?.Dispose();
        _session = null;
    }

    private void Quit()
    {
        _tray?.Dispose();
        _tray = null;
        _mainWindow?.Dispose();
        _mainWindow = null;
        _session?.Dispose();
        _session = null;
        if (_held)
        {
            _app.Release();
            _held = false;
        }

        _app.Quit();
    }
}

/// <summary>
/// XDG autostart helper. Writes a user autostart .desktop that launches the
/// app as a normal window (GNOME has no tray). Flatpak uses `flatpak run`.
/// </summary>
internal static class Autostart
{
    private static string DesktopFileName =>
        IsFlatpak
            ? $"{AppConstants.ApplicationId}.desktop"
            : "copilot-desktop-gtk.desktop";

    private static string DesktopFilePath
    {
        get
        {
            // Prefer real host config when Flatpak grants xdg-config/autostart.
            var configHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
            if (string.IsNullOrEmpty(configHome))
            {
                configHome = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    ".config");
            }

            return Path.Combine(configHome, "autostart", DesktopFileName);
        }
    }

    private static bool IsFlatpak =>
        !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("FLATPAK_ID")) ||
        File.Exists("/.flatpak-info");

    public static bool IsEnabled()
    {
        if (File.Exists(DesktopFilePath))
        {
            try
            {
                var text = File.ReadAllText(DesktopFilePath);
                // Hidden=true means user disabled an otherwise present entry.
                if (text.Contains("Hidden=true", StringComparison.OrdinalIgnoreCase) ||
                    text.Contains("X-GNOME-Autostart-enabled=false", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                return true;
            }
            catch
            {
                return true;
            }
        }

        // Host default-on path: system autostart without a user override.
        if (!IsFlatpak)
        {
            var system = $"/etc/xdg/autostart/{DesktopFileName}";
            if (File.Exists(system) || File.Exists("/etc/xdg/autostart/copilot-desktop-gtk.desktop"))
            {
                return true;
            }
        }

        return false;
    }

    public static void SetEnabled(bool enabled)
    {
        var path = DesktopFilePath;
        // GNOME-first: open a normal window on login. No --tray.
        var execLine = ResolveExecutable();
        var icon = IsFlatpak ? AppConstants.ApplicationId : "copilot-desktop-gtk";

        if (enabled)
        {
            var dir = Path.GetDirectoryName(path)!;
            Directory.CreateDirectory(dir);
            var contents =
                $"""
                [Desktop Entry]
                Type=Application
                Version=1.5
                Name={AppConstants.AppName}
                Comment={AppConstants.Description}
                Exec={execLine}
                Icon={icon}
                Terminal=false
                Categories=Network;GNOME;GTK;
                StartupNotify=false
                NoDisplay=true
                X-GNOME-Autostart-enabled=true
                X-GNOME-Autostart-Delay=3
                """;
            File.WriteAllText(path, contents);
        }
        else if (File.Exists(path))
        {
            // Disable rather than only delete: if a system autostart
            // entry exists, deleting the user file would re-enable it.
            var contents =
                $"""
                [Desktop Entry]
                Type=Application
                Version=1.5
                Name={AppConstants.AppName}
                Comment={AppConstants.Description}
                Exec={execLine}
                Icon={icon}
                Terminal=false
                Hidden=true
                X-GNOME-Autostart-enabled=false
                NoDisplay=true
                """;
            File.WriteAllText(path, contents);
        }
        else if (!IsFlatpak &&
                 (File.Exists("/etc/xdg/autostart/copilot-desktop-gtk.desktop") ||
                  File.Exists($"/etc/xdg/autostart/{DesktopFileName}")))
        {
            var dir = Path.GetDirectoryName(path)!;
            Directory.CreateDirectory(dir);
            var contents =
                $"""
                [Desktop Entry]
                Type=Application
                Version=1.5
                Name={AppConstants.AppName}
                Comment={AppConstants.Description}
                Exec={execLine}
                Icon=copilot-desktop-gtk
                Terminal=false
                Hidden=true
                X-GNOME-Autostart-enabled=false
                NoDisplay=true
                """;
            File.WriteAllText(path, contents);
        }
    }

    private static string ResolveExecutable()
    {
        if (IsFlatpak)
        {
            // Host session must launch through flatpak so sandbox finish-args apply.
            return $"flatpak run {AppConstants.ApplicationId}";
        }

        try
        {
            var processPath = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(processPath) && File.Exists(processPath))
            {
                return processPath;
            }
        }
        catch
        {
            // ignore
        }

        return "copilot-desktop-gtk";
    }
}

internal static class ResourceLoader
{
    public static string LoadText(string logicalName)
    {
        var asm = Assembly.GetExecutingAssembly();
        using var stream = asm.GetManifestResourceStream(logicalName)
            ?? throw new InvalidOperationException($"missing embedded resource: {logicalName}");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    public static byte[] LoadBytes(string logicalName)
    {
        var asm = Assembly.GetExecutingAssembly();
        using var stream = asm.GetManifestResourceStream(logicalName)
            ?? throw new InvalidOperationException($"missing embedded resource: {logicalName}");
        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        return ms.ToArray();
    }
}
