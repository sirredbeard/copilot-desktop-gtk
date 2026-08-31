using System.Runtime.InteropServices;

namespace CopilotDesktopGtk;

/// <summary>
/// Optional StatusNotifier tray via host libayatana-appindicator3 (soft DllImport).
///
/// Off by default. Ayatana is a Gtk3 library and this process runs Gtk4, so
/// loading it breaks the Gtk4 display. See TryCreate. Set COPILOT_TRAY_AYATANA=1
/// to try it anyway on a host that has the library.
///
/// Stock GNOME has no tray host. We only construct this when the opt-in is set,
/// a StatusNotifier watcher is on the session bus, AND the host library loads.
/// Otherwise the app is a normal window (close quits, header menu has Quit).
/// Not bundled in Flatpak.
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private const string Lib = "libayatana-appindicator3.so.1";
    private const string OptInVariable = "COPILOT_TRAY_AYATANA";

    private readonly IntPtr _indicator;
    private readonly IntPtr _menu;
    private bool _disposed;

    // Keep delegates rooted so the GC does not collect callbacks the C side still holds.
    private readonly List<GCHandle> _pins = [];
    private readonly Action _onShowHide;
    private readonly Action _onAbout;
    private readonly Action _onQuit;
    private readonly Action<bool> _onAutostartChanged;
    private IntPtr _autostartItem;

    private TrayIcon(
        IntPtr indicator,
        IntPtr menu,
        Action onShowHide,
        Action onAbout,
        Action onQuit,
        Action<bool> onAutostartChanged)
    {
        _indicator = indicator;
        _menu = menu;
        _onShowHide = onShowHide;
        _onAbout = onAbout;
        _onQuit = onQuit;
        _onAutostartChanged = onAutostartChanged;
    }

    public static TrayIcon? TryCreate(
        Action onShowHide,
        Action onAbout,
        Action onQuit,
        Action<bool> onAutostartChanged,
        bool autostartEnabled)
    {
        // libayatana-appindicator3.so.1 has a DT_NEEDED entry for libgtk-3.so.0,
        // and Program.Main has already run Gtk4 init. Two Gtk versions in one
        // process cannot share the GdkDisplayManager type. The second one to
        // register fails and the Gtk4 window never appears:
        //   cannot register existing type 'GdkDisplayManager'
        // So the Gtk3 path stays off unless the user asks for it. Issue #3.
        if (Environment.GetEnvironmentVariable(OptInVariable) != "1")
        {
            return null;
        }

        // Probe the library before any native call. A missing library must not
        // pull libgtk-3 into this process through a failed DllImport.
        if (!NativeLibrary.TryLoad(Lib, out _))
        {
            return null;
        }

        try
        {
            // Ensure GTK is up; appindicator menus are Gtk3 menus historically.
            // Ayatana still links Gtk3 menu widgets even when the app is Gtk4.
            // We build a plain Gtk3 menu through the appindicator helpers.
            Native.gtk_init_check(IntPtr.Zero, IntPtr.Zero);

            // Flatpak exports the app-id icon name; RPM uses the short name.
            var iconName = File.Exists("/.flatpak-info")
                ? AppConstants.ApplicationId
                : "copilot-desktop-gtk";

            var indicator = Native.app_indicator_new(
                AppConstants.ApplicationId,
                iconName,
                Native.APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
            if (indicator == IntPtr.Zero)
            {
                Console.Error.WriteLine("tray: app_indicator_new returned null");
                return null;
            }

            Native.app_indicator_set_status(indicator, Native.APP_INDICATOR_STATUS_ACTIVE);
            Native.app_indicator_set_title(indicator, AppConstants.AppName);
            Native.app_indicator_set_icon_full(indicator, iconName, AppConstants.AppName);

            var menu = Native.gtk_menu_new();
            var tray = new TrayIcon(indicator, menu, onShowHide, onAbout, onQuit, onAutostartChanged);

            tray.AddMenuItem($"Show/Hide ({AppConstants.ShowHideShortcutLabel})", tray.HandleShowHide);
            tray.AddSeparator();
            tray._autostartItem = tray.AddCheckMenuItem("Autostart", autostartEnabled, tray.HandleAutostart);
            tray.AddSeparator();
            tray.AddMenuItem("About", tray.HandleAbout);
            tray.AddMenuItem("Quit", tray.HandleQuit);

            Native.gtk_widget_show_all(menu);
            Native.app_indicator_set_menu(indicator, menu);

            Console.WriteLine("tray: ayatana appindicator active");
            return tray;
        }
        catch (DllNotFoundException ex)
        {
            Console.Error.WriteLine($"tray unavailable (missing library): {ex.Message}");
            return null;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"tray init failed: {ex.Message}");
            return null;
        }
    }

    private void HandleShowHide() => _onShowHide();
    private void HandleAbout() => _onAbout();
    private void HandleQuit() => _onQuit();

    private void HandleAutostart()
    {
        if (_autostartItem == IntPtr.Zero)
        {
            return;
        }

        var active = Native.gtk_check_menu_item_get_active(_autostartItem);
        _onAutostartChanged(active);
    }

    private void AddMenuItem(string label, Action action)
    {
        var item = Native.gtk_menu_item_new_with_label(label);
        ConnectActivate(item, action);
        Native.gtk_menu_shell_append(_menu, item);
        Native.gtk_widget_show(item);
    }

    private IntPtr AddCheckMenuItem(string label, bool active, Action action)
    {
        var item = Native.gtk_check_menu_item_new_with_label(label);
        Native.gtk_check_menu_item_set_active(item, active);
        ConnectActivate(item, action);
        Native.gtk_menu_shell_append(_menu, item);
        Native.gtk_widget_show(item);
        return item;
    }

    private void AddSeparator()
    {
        var item = Native.gtk_separator_menu_item_new();
        Native.gtk_menu_shell_append(_menu, item);
        Native.gtk_widget_show(item);
    }

    private void ConnectActivate(IntPtr widget, Action action)
    {
        Native.GCallback cb = _ =>
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"tray action failed: {ex.Message}");
            }
        };
        _pins.Add(GCHandle.Alloc(cb));
        Native.g_signal_connect_data(widget, "activate", cb, IntPtr.Zero, IntPtr.Zero, 0);
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
            if (_indicator != IntPtr.Zero)
            {
                Native.app_indicator_set_status(_indicator, Native.APP_INDICATOR_STATUS_PASSIVE);
            }
        }
        catch
        {
            // ignore
        }

        foreach (var pin in _pins)
        {
            if (pin.IsAllocated)
            {
                pin.Free();
            }
        }

        _pins.Clear();
    }

    private static class Native
    {
        public const int APP_INDICATOR_CATEGORY_APPLICATION_STATUS = 0;
        public const int APP_INDICATOR_STATUS_PASSIVE = 0;
        public const int APP_INDICATOR_STATUS_ACTIVE = 1;

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void GCallback(IntPtr data);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr app_indicator_new(string id, string iconName, int category);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void app_indicator_set_status(IntPtr self, int status);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void app_indicator_set_menu(IntPtr self, IntPtr menu);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void app_indicator_set_title(IntPtr self, string title);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void app_indicator_set_icon_full(IntPtr self, string iconName, string iconDesc);

        // Gtk3 symbols used by the indicator menu. libgtk-3 is a dependency of
        // libayatana-appindicator3 even on a Gtk4 desktop session.
        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern bool gtk_init_check(IntPtr argc, IntPtr argv);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr gtk_menu_new();

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr gtk_menu_item_new_with_label(string label);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr gtk_check_menu_item_new_with_label(string label);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern void gtk_check_menu_item_set_active(IntPtr checkMenuItem, bool isActive);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern bool gtk_check_menu_item_get_active(IntPtr checkMenuItem);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr gtk_separator_menu_item_new();

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern void gtk_menu_shell_append(IntPtr menuShell, IntPtr child);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern void gtk_widget_show(IntPtr widget);

        [DllImport("libgtk-3.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern void gtk_widget_show_all(IntPtr widget);

        [DllImport("libgobject-2.0.so.0", CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong g_signal_connect_data(
            IntPtr instance,
            string detailedSignal,
            GCallback cHandler,
            IntPtr data,
            IntPtr destroyData,
            int connectFlags);
    }
}
