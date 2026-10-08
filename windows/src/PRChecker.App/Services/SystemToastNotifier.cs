using System.Runtime.InteropServices;
using System.Security;
using Microsoft.Win32;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;

namespace PRChecker.App.Services;

/// <summary>
/// Notifications through Windows' built-in toast API, used when the Windows App SDK's notifications
/// can't register (they need the Windows App Runtime "Singleton" package, which self-contained apps
/// don't install). Needs only a per-user registry entry with the app's name and icon. Clicks are
/// handled while the app is running, which a tray app normally is.
/// </summary>
internal sealed partial class SystemToastNotifier
{
    private const string AppUserModelId = "Berke.PRChecker";
    private const string RegistryKey = @"Software\Classes\AppUserModelId\" + AppUserModelId;
    private const int KeptToasts = 20;

    private readonly ToastNotifier _notifier;
    /// <summary>Recent toasts kept alive so their Activated handlers still fire.</summary>
    private readonly Queue<ToastNotification> _recent = new();

    private SystemToastNotifier(ToastNotifier notifier) => _notifier = notifier;

    public event Action<string>? LinkClicked;

    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int SetCurrentProcessExplicitAppUserModelID(string appId);

    public static SystemToastNotifier Create()
    {
        using (var key = Registry.CurrentUser.CreateSubKey(RegistryKey))
        {
            key.SetValue("DisplayName", "PR Checker");
            key.SetValue("IconUri", Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        }
        Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(AppUserModelId));
        return new SystemToastNotifier(ToastNotificationManager.CreateToastNotifier(AppUserModelId));
    }

    /// <summary>Removes the registry entry; called when the app is uninstalled.</summary>
    public static void Unregister() => Registry.CurrentUser.DeleteSubKeyTree(RegistryKey, throwOnMissingSubKey: false);

    public bool IsBlockedBySystem => _notifier.Setting != NotificationSetting.Enabled;

    public void Show(IEnumerable<string> lines, string? url)
    {
        var texts = string.Concat(lines.Select(line => $"<text>{SecurityElement.Escape(line)}</text>"));
        var launch = url is null ? "" : $" launch=\"{SecurityElement.Escape(url)}\"";
        var xml = new XmlDocument();
        xml.LoadXml($"<toast{launch}><visual><binding template=\"ToastGeneric\">{texts}</binding></visual></toast>");

        var toast = new ToastNotification(xml);
        if (url is not null) toast.Activated += (_, _) => LinkClicked?.Invoke(url);
        _recent.Enqueue(toast);
        while (_recent.Count > KeptToasts) _recent.Dequeue();
        _notifier.Show(toast);
    }

    public static void Clear() => ToastNotificationManager.History.Clear(AppUserModelId);
}
