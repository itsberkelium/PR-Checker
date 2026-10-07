using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>Windows notifications; clicking one opens its PR (if it's on the configured server).</summary>
internal sealed class WindowsNotifier : INotifier
{
    private const string UrlArgument = "url";

    /// <summary>Called on a background thread with the clicked notification's link.</summary>
    public event Action<string>? LinkClicked;

    public void Register()
    {
        AppNotificationManager.Default.NotificationInvoked += (_, args) => HandleArguments(args.Arguments);
        AppNotificationManager.Default.Register();
    }

    public void Unregister() => AppNotificationManager.Default.Unregister();

    /// <summary>For a launch caused by clicking a notification while the app wasn't running.</summary>
    public void HandleArguments(IDictionary<string, string> arguments)
    {
        if (arguments.TryGetValue(UrlArgument, out var url)) LinkClicked?.Invoke(url);
    }

    /// <summary>What Windows allows, independent of the app's own Notifications switch.</summary>
    public static bool IsBlockedBySystem => AppNotificationManager.Default.Setting != AppNotificationSetting.Enabled;

    public void Post(Change change, bool showDetails)
    {
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
        AppNotificationManager.Default.Show(builder.BuildNotification());
    }

    /// <summary>Has no link, so clicking it just dismisses it.</summary>
    public static void SendTest() =>
        AppNotificationManager.Default.Show(new AppNotificationBuilder()
            .AddText("PR Checker notifications work")
            .AddText("Click a notification to open its pull request.")
            .BuildNotification());

    public void RemoveDelivered() => _ = AppNotificationManager.Default.RemoveAllAsync();
}
