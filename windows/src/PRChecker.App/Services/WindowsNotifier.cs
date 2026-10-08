using System.Runtime.InteropServices;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>
/// Windows notifications; clicking one opens its PR (if it's on the configured server).
/// Uses the Windows App SDK's notifications when they register, otherwise Windows' built-in
/// toast API (<see cref="SystemToastNotifier"/>). If neither works, every call is a no-op and
/// <see cref="UnavailableReason"/> says why, so the rest of the app keeps working.
/// </summary>
internal sealed class WindowsNotifier : INotifier
{
    private const string UrlArgument = "url";

    private bool _appSdk;
    private SystemToastNotifier? _system;

    /// <summary>Called on a background thread with the clicked notification's link.</summary>
    public event Action<string>? LinkClicked;

    public bool IsAvailable => _appSdk || _system is not null;
    public string? UnavailableReason { get; private set; }

    public void Register()
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, args) => HandleArguments(args.Arguments);
            AppNotificationManager.Default.Register();
            _appSdk = true;
            Log.Info("Notifications registered (Windows App SDK)");
            return;
        }
        catch (Exception error) when (IsPlatformError(error))
        {
            Log.Error("Windows App SDK notifications unavailable; trying Windows' built-in notifications", error);
            UnavailableReason = FirstLine(error.Message);
        }

        try
        {
            _system = SystemToastNotifier.Create();
            _system.LinkClicked += url => LinkClicked?.Invoke(url);
            UnavailableReason = null;
            Log.Info("Notifications registered (built-in Windows toasts)");
        }
        catch (Exception error) when (IsPlatformError(error))
        {
            Log.Error("Built-in notifications unavailable too; continuing without notifications", error);
            UnavailableReason = FirstLine(error.Message);
        }
    }

    public void Unregister()
    {
        if (!_appSdk) return;
        Try("unregister notifications", () => AppNotificationManager.Default.Unregister());
        _appSdk = false;
    }

    /// <summary>For a launch caused by clicking a notification while the app wasn't running.</summary>
    public void HandleArguments(IDictionary<string, string> arguments)
    {
        if (arguments.TryGetValue(UrlArgument, out var url)) LinkClicked?.Invoke(url);
    }

    /// <summary>Windows' own notification switch for PR Checker is off (only meaningful when available).</summary>
    public bool IsBlockedBySystem
    {
        get
        {
            try
            {
                if (_appSdk) return AppNotificationManager.Default.Setting != AppNotificationSetting.Enabled;
                return _system?.IsBlockedBySystem ?? false;
            }
            catch (Exception error) when (IsPlatformError(error)) { return false; }
        }
    }

    public void Post(Change change, bool showDetails)
    {
        // No titles, names or outcomes when details are off, e.g. for screen sharing or a locked screen.
        var lines = showDetails
            ? [change.Title, .. change.Body.Split('\n')]
            : new[] { "PR Checker", "A pull request has an update. Click to open it." };
        Show(lines, change.Url.AbsoluteUri, "show a notification");
    }

    /// <summary>Has no link, so clicking it just dismisses it.</summary>
    public void SendTest() =>
        Show(["PR Checker notifications work", "Click a notification to open its pull request."], url: null, "show the test notification");

    public void RemoveDelivered()
    {
        if (_appSdk) Try("clear notifications", () => _ = AppNotificationManager.Default.RemoveAllAsync());
        else if (_system is not null) Try("clear notifications", SystemToastNotifier.Clear);
    }

    private void Show(string[] lines, string? url, string action)
    {
        if (_appSdk)
        {
            var builder = new AppNotificationBuilder();
            if (url is not null) builder.AddArgument(UrlArgument, url);
            foreach (var line in lines) builder.AddText(line);
            Try(action, () => AppNotificationManager.Default.Show(builder.BuildNotification()));
        }
        else if (_system is { } system)
        {
            Try(action, () => system.Show(lines, url));
        }
    }

    private static void Try(string action, Action operation)
    {
        try { operation(); }
        catch (Exception error) when (IsPlatformError(error)) { Log.Error($"Couldn't {action}", error); }
    }

    private static bool IsPlatformError(Exception error) =>
        error is COMException or InvalidOperationException or UnauthorizedAccessException or FileNotFoundException or ArgumentException;

    private static string FirstLine(string message) => message.Split('\n', 2)[0].Trim();
}
