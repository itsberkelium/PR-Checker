using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using PRChecker.App.Services;
using PRChecker.App.Views;
using PRChecker.Core;

namespace PRChecker.App;

/// <summary>A tray app: no main window, just the tray icon, the PR list popup and Settings.</summary>
public sealed partial class App : Application, IDisposable
{
    private readonly DispatcherQueue _dispatcher = DispatcherQueue.GetForCurrentThread();
    private readonly WindowsNotifier _notifier = new();
    private readonly UpdateService _updates = new();
    private PrStore? _store;
    private TrayController? _tray;
    private PopupWindow? _popup;
    private SettingsWindow? _settingsWindow;
    private DispatcherQueueTimer? _updateTimer;

    public App()
    {
        InitializeComponent();
        // A tray app keeps running with no windows open; only Quit (Exit) ends it.
        DispatcherShutdownMode = DispatcherShutdownMode.OnExplicitShutdown;
        UnhandledException += (_, e) =>
        {
            Log.Error("Unhandled UI exception", e.Exception);
            e.Handled = true; // keep the tray app alive; the error is in the log
        };
        _notifier.LinkClicked += url => _dispatcher.TryEnqueue(() => { if (_store is { } store) Platform.OpenLink(url, store.Settings); });
        _notifier.Register();
    }

    internal PrStore Store => _store!;
    internal UpdateService Updates => _updates;
    internal WindowsNotifier Notifier => _notifier;

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Log.Info("Launched");
        var files = new JsonFileStore(Platform.DataDirectory);
        var settings = new AppSettings(files, new CredentialTokenStore());
        _store = new PrStore(settings, files, _notifier);

        try
        {
            _tray = new TrayController(this);
            _tray.Create();
            Log.Info("Tray icon created");
        }
        catch (Exception error) when (error is COMException or InvalidOperationException or ArgumentException or IOException)
        {
            Log.Error("Couldn't create the tray icon", error);
        }

        // Later activations: a second launch shows the list; a notification click opens its PR.
        AppInstance.GetCurrent().Activated += (_, activation) => _dispatcher.TryEnqueue(() => HandleActivation(activation));
        // This launch: only act on a notification click, so starting at login stays quiet.
        var launch = AppInstance.GetCurrent().GetActivatedEventArgs();
        if (launch.Kind == ExtendedActivationKind.AppNotification) HandleActivation(launch);

        var configured = _store.IsConfigured;
        Log.Info(configured ? "Connected; polling" : "Not connected; opening Settings");
        if (configured) _store.Start();
        else ShowSettings(SettingsWindow.Page.Bitbucket);

        StartUpdateChecks();
    }

    /// <summary>A notification click, or another launch while running.</summary>
    private void HandleActivation(AppActivationArguments activation)
    {
        if (activation.Kind == ExtendedActivationKind.AppNotification && activation.Data is AppNotificationActivatedEventArgs notification)
            _notifier.HandleArguments(notification.Arguments);
        else if (activation.Kind == ExtendedActivationKind.Launch && _store is { IsConfigured: true })
            ShowPopup();
    }

    internal void ShowPopup()
    {
        _popup ??= new PopupWindow(this);
        _popup.ShowNearTray();
    }

    internal void TogglePopup()
    {
        if (_popup is { IsShown: true }) _popup.HideWindow();
        else ShowPopup();
    }

    internal void ShowSettings(SettingsWindow.Page page = SettingsWindow.Page.General)
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(this);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }
        _settingsWindow.Show(page);
    }

    internal void Quit()
    {
        if (!Platform.ConfirmQuit()) return;
        Dispose();
        Exit();
    }

    private void StartUpdateChecks()
    {
        _updateTimer = _dispatcher.CreateTimer();
        _updateTimer.Interval = TimeSpan.FromHours(6);
        _updateTimer.Tick += async (_, _) => await CheckForUpdatesAsync(userInitiated: false);
        _updateTimer.Start();
        _ = CheckForUpdatesAsync(userInitiated: false);
    }

    /// <summary>Scheduled checks run once a week; a manual check always runs and reports the result.</summary>
    internal async Task CheckForUpdatesAsync(bool userInitiated)
    {
        if (!userInitiated && !_updates.IsDue) return;
        try
        {
            var update = await _updates.CheckAsync();
            if (update is not null && await UpdatePrompt.AskAsync(update.TargetFullRelease.Version.ToString()))
                await _updates.InstallAndRestartAsync(update);
            else if (userInitiated) UpdatePrompt.Inform(_updates.IsInstalled ? "PR Checker is up to date." : "Updates are only available in installed builds.");
        }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException)
        {
            if (userInitiated) UpdatePrompt.Inform($"Couldn't check for updates: {error.Message}");
        }
    }

    public void Dispose()
    {
        _updateTimer?.Stop();
        _store?.Dispose();
        _tray?.Dispose();
        _notifier.Unregister();
    }
}
