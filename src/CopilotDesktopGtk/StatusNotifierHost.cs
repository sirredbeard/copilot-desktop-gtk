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
    /// True when a StatusNotifier host is registered with the session
    /// watcher (<c>IsStatusNotifierHostRegistered</c>). Missing watcher,
    /// failed call, or property false all mean no tray. Calls the watcher
    /// name directly so Flatpak does not need talk access to
    /// <c>org.freedesktop.DBus</c> for <c>NameHasOwner</c>.
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

            // Standard SNI path. Missing watcher => CallSync throws/null.
            // Watcher present but no host => property is false. Both: no tray.
            var args = GLib.Variant.NewTuple(
            [
                GLib.Variant.NewString("org.kde.StatusNotifierWatcher"),
                GLib.Variant.NewString("IsStatusNotifierHostRegistered"),
            ]);
            var reply = bus.CallSync(
                busName: WatcherName,
                objectPath: "/StatusNotifierWatcher",
                interfaceName: "org.freedesktop.DBus.Properties",
                methodName: "Get",
                parameters: args,
                replyType: GLib.VariantType.New("(v)"),
                flags: Gio.DBusCallFlags.None,
                timeoutMsec: 1500,
                cancellable: null);

            if (reply is null)
            {
                return false;
            }

            using var variant = reply.GetChildValue(0);
            using var inner = variant.GetVariant();
            return inner.GetBoolean();
        }
        catch (Exception ex)
        {
            // ServiceUnknown / name has no owner is normal on plain GNOME.
            // Only log unexpected probe failures.
            var msg = ex.Message ?? string.Empty;
            if (!msg.Contains("ServiceUnknown", StringComparison.Ordinal)
                && !msg.Contains("NameHasNoOwner", StringComparison.Ordinal)
                && !msg.Contains("was not provided by any", StringComparison.OrdinalIgnoreCase))
            {
                Console.Error.WriteLine($"statusnotifier probe: {msg}");
            }

            return false;
        }
    }
}
