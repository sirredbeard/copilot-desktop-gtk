namespace CopilotDesktopGtk;

/// <summary>
/// Detects a StatusNotifierItem host on the session bus.
/// Stock GNOME has none unless the user installs an AppIndicator / SNI
/// extension. Without a host, an AppIndicator library can still load and
/// still draw nothing useful, so we treat "no watcher" as "no tray".
/// </summary>
internal static class StatusNotifierHost
{
    public const string WatcherName = "org.kde.StatusNotifierWatcher";

    /// <summary>
    /// True when something on the session bus owns the SNI watcher name.
    /// </summary>
    public static bool IsAvailable()
    {
        try
        {
            var bus = Gio.Functions.BusGetSync(Gio.BusType.Session, null);
            if (bus is null)
            {
                return false;
            }

            var args = GLib.Variant.NewTuple([GLib.Variant.NewString(WatcherName)]);
            var reply = bus.CallSync(
                busName: "org.freedesktop.DBus",
                objectPath: "/org/freedesktop/DBus",
                interfaceName: "org.freedesktop.DBus",
                methodName: "NameHasOwner",
                parameters: args,
                replyType: GLib.VariantType.New("(b)"),
                flags: Gio.DBusCallFlags.None,
                timeoutMsec: 1500,
                cancellable: null);

            if (reply is null)
            {
                return false;
            }

            using var child = reply.GetChildValue(0);
            return child.GetBoolean();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"statusnotifier probe: {ex.Message}");
            return false;
        }
    }
}
