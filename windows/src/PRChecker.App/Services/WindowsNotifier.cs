using System.Runtime.InteropServices;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>
/// Windows notifications; clicking one opens its PR (if it's on the configured server).
/// Registration can fail on some PCs (e.g. locked-down ones); then every call is a no-op and
/// <see cref="UnavailableReason"/> says why, so the rest of the app keeps working.
/// </summary>
internal sealed class WindowsNotifier : INotifier
{
    private const string UrlArgument = "url";

    /// <summary>Called on a background thread with the clicked notification's link.</summary>
    public event Action<string>? LinkClicked;

    public bool IsAvailable { get; private set; }
    public string? UnavailableReason { get; private set; }

    public void Register()
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, args) => HandleArguments(args.Arguments);
            AppNotificationManager.Default.Register();
            IsAvailable = true;
            Log.Info("Notifications registered");
        }
        catch (Exception error) when (IsPlatformError(error))
        {
            UnavailableReason = FirstLine(error.Message);
            Log.Error("Couldn't register for notifications; continuing without them", error);
        }
    }

    public void Unregister()
    {
        if (!IsAvailable) return;
        Try("unregister notifications", () => AppNotificationManager.Default.Unregister());
        IsAvailable = false;
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
            if (!IsAvailable) return false;
            try { return AppNotificationManager.Default.Setting != AppNotificationSetting.Enabled; }
            catch (Exception error) when (IsPlatformError(error)) { return false; }
        }
    }

    public void Post(Change change, bool showDetails)
    {
        if (!IsAvailable) return;
        var builder = new AppNotificationBuilder().AddArgument(UrlArgument, change.Url.AbsoluteUri);
        if (showDetails)
        {
            builder.AddText(change.Title);
            foreach (var line in change.Body.Split('\n')) builder.AddText(line);
        }
        else
        {
            // No titles, names or outcomes, e.g. for screen sharing or a locked screen.
            builder.AddText("PR Checker").AddText("A pull request has an update. Click to open it.");
        }
        Try("show a notification", () => AppNotificationManager.Default.Show(builder.BuildNotification()));
    }

    /// <summary>Has no link, so clicking it just dismisses it.</summary>
    public void SendTest()
    {
        if (!IsAvailable) return;
        Try("show the test notification", () => AppNotificationManager.Default.Show(new AppNotificationBuilder()
            .AddText("PR Checker notifications work")
            .AddText("Click a notification to open its pull request.")
            .BuildNotification()));
    }

    public void RemoveDelivered()
    {
        if (!IsAvailable) return;
        Try("clear notifications", () => _ = AppNotificationManager.Default.RemoveAllAsync());
    }

    private static void Try(string action, Action operation)
    {
        try { operation(); }
        catch (Exception error) when (IsPlatformError(error)) { Log.Error($"Couldn't {action}", error); }
    }

    private static bool IsPlatformError(Exception error) =>
        error is COMException or InvalidOperationException or UnauthorizedAccessException or FileNotFoundException;

    private static string FirstLine(string message) => message.Split('\n', 2)[0].Trim();
}
