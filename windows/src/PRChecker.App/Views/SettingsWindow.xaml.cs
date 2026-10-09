using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PRChecker.App.Services;
using PRChecker.Core;
using Windows.Graphics;

namespace PRChecker.App.Views;

/// <summary>
/// General, Bitbucket and About tabs. The server URL and token are drafts until Save &amp; Connect
/// validates them; nothing is sent anywhere while editing.
/// </summary>
public sealed partial class SettingsWindow : Window
{
    public enum Page { General, Bitbucket, About }

    private readonly App _app;
    private bool _loading;

    internal SettingsWindow(App app)
    {
        _app = app;
        InitializeComponent();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        var scale = Content.XamlRoot?.RasterizationScale ?? 1.0;
        AppWindow.Resize(new SizeInt32((int)(640 * scale), (int)(720 * scale)));
        Closed += (_, _) =>
        {
            TokenBox.Password = "";
            Localizer.Changed -= OnLanguageApplied;
        };
        Activated += (_, _) => RefreshNotificationState();
        Localizer.Changed += OnLanguageApplied;
        ApplyStrings();
        Load();
    }

    /// <summary>All visible text, from L10n; called again whenever the language changes.</summary>
    private void ApplyStrings()
    {
        var loading = _loading;
        _loading = true;
        Title = L10n.SettingsWindowTitle;
        GeneralItem.Content = L10n.TabGeneral;
        BitbucketItem.Content = L10n.TabBitbucket;
        AboutItem.Content = L10n.TabAbout;

        NotificationsToggle.Header = L10n.Notifications;
        OpenNotificationSettingsButton.Content = L10n.OpenNotificationSettings;
        TestNotificationButton.Content = L10n.SendTestNotification;
        DetailsToggle.Header = L10n.ShowDetailsInNotifications;
        DetailsHint.Text = L10n.ShowDetailsHint;
        OpenAtLoginToggle.Header = L10n.OpenAtLogin;
        RefreshBox.Header = L10n.CheckEvery;
        var refresh = RefreshBox.SelectedIndex;
        RefreshBox.Items.Clear();
        foreach (var minutes in AppSettings.RefreshOptions) RefreshBox.Items.Add(L10n.MinutesShort(minutes));
        RefreshBox.SelectedIndex = refresh;
        LanguageBox.Header = L10n.Language;
        var language = LanguageBox.SelectedIndex;
        LanguageBox.Items.Clear();
        // Language names stay in their own language, so anyone can find theirs.
        foreach (var name in new[] { L10n.LanguageSystem, "English", "Türkçe" }) LanguageBox.Items.Add(name);
        LanguageBox.SelectedIndex = language;

        ServerBox.Header = L10n.ServerURL;
        TokenBox.Header = L10n.AccessToken;
        TokenHint.Text = L10n.TokenHintWindows;
        ConnectButton.Content = L10n.SaveAndConnect;
        SignOutButton.Content = L10n.SignOut;
        FiltersTitle.Text = L10n.Filters;
        HideDraftsToggle.Header = L10n.HideDrafts;
        FilterBox.Header = L10n.OnlyTheseRepos;
        FilterBox.PlaceholderText = L10n.FilterAllPlaceholder;
        FilterHint.Text = L10n.FilterHint;

        CheckForUpdatesButton.Content = L10n.CheckForUpdates;
        UpdateLastCheck();
        UpdateTokenHint();
        RefreshNotificationState();
        _loading = loading;
    }

    private void OnLanguageApplied() => DispatcherQueue.TryEnqueue(ApplyStrings);

    private void OnLanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || LanguageBox.SelectedIndex < 0) return;
        Settings.Language = (LanguagePreference)LanguageBox.SelectedIndex;
    }

    private AppSettings Settings => _app.Store.Settings;

    internal void Show(Page page)
    {
        Navigation.SelectedItem = page switch
        {
            Page.Bitbucket => BitbucketItem,
            Page.About => AboutItem,
            _ => GeneralItem,
        };
        Activate();
    }

    private void Load()
    {
        _loading = true;
        NotificationsToggle.IsOn = Settings.NotificationsEnabled;
        DetailsToggle.IsOn = Settings.NotificationDetails;
        OpenAtLoginToggle.IsOn = Platform.OpenAtLogin;
        RefreshBox.SelectedIndex = Array.IndexOf(AppSettings.RefreshOptions, Settings.RefreshMinutes);
        LanguageBox.SelectedIndex = (int)Settings.Language;
        ServerBox.Text = Settings.SavedServerUrl;
        HideDraftsToggle.IsOn = Settings.HideDrafts;
        FilterBox.Text = Settings.RepoFilter;
        VersionText.Text = $"PR Checker {Platform.Version}";
        UpdateTokenHint();
        RefreshNotificationState();
        _loading = false;
    }

    private void OnNavigate(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var tag = (args.SelectedItem as NavigationViewItem)?.Tag as string;
        GeneralPage.Visibility = tag == "General" ? Visibility.Visible : Visibility.Collapsed;
        BitbucketPage.Visibility = tag == "Bitbucket" ? Visibility.Visible : Visibility.Collapsed;
        AboutPage.Visibility = tag == "About" ? Visibility.Visible : Visibility.Collapsed;
        if (tag == "About") UpdateLastCheck();
    }

    private void UpdateLastCheck() =>
        LastCheckText.Text = _app.Updates.LastCheck is { } last ? L10n.LastChecked(PrRow.Relative(last)) : L10n.CheckedWeekly;

    // MARK: General

    private void RefreshNotificationState()
    {
        var notifier = _app.Notifier;
        var blocked = Settings.NotificationsEnabled && (notifier.IsBlockedBySystem || !notifier.IsAvailable);
        NotificationsBlocked.Title = notifier.IsAvailable ? L10n.BlockedWindowsTitle : L10n.UnavailableTitle;
        NotificationsBlocked.Message = notifier.IsAvailable
            ? L10n.BlockedWindowsMessage
            : L10n.UnavailableMessage(notifier.UnavailableReason ?? "");
        NotificationsBlocked.ActionButton.Visibility = notifier.IsAvailable ? Visibility.Visible : Visibility.Collapsed;
        NotificationsBlocked.IsOpen = blocked;
        TestNotificationButton.Visibility = Settings.NotificationsEnabled && !blocked ? Visibility.Visible : Visibility.Collapsed;
        DetailsToggle.IsEnabled = Settings.NotificationsEnabled;
    }

    private void OnNotificationsToggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Settings.NotificationsEnabled = NotificationsToggle.IsOn;
        if (!NotificationsToggle.IsOn) _app.Notifier.RemoveDelivered();
        RefreshNotificationState();
    }

    private void OnDetailsToggled(object sender, RoutedEventArgs e)
    {
        if (!_loading) Settings.NotificationDetails = DetailsToggle.IsOn;
    }

    private void OnSendTest(object sender, RoutedEventArgs e) => _app.Notifier.SendTest();

    private void OnOpenNotificationSettings(object sender, RoutedEventArgs e) => Platform.OpenNotificationSettings();

    private void OnOpenAtLoginToggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Platform.OpenAtLogin = OpenAtLoginToggle.IsOn;
        Settings.OpenAtLogin = OpenAtLoginToggle.IsOn;
    }

    private void OnRefreshChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || RefreshBox.SelectedIndex < 0) return;
        Settings.RefreshMinutes = AppSettings.RefreshOptions[RefreshBox.SelectedIndex];
        if (_app.Store.IsConfigured) _app.Store.Start();
    }

    // MARK: Bitbucket

    /// <summary>The saved token can be reused only when the draft is the same server.</summary>
    private bool CanReuseSavedToken =>
        ServerAddress.TryParse(ServerBox.Text, out var draft) && draft == Settings.Server && Settings.HasToken(draft!);

    private void UpdateTokenHint()
    {
        TokenBox.PlaceholderText = CanReuseSavedToken ? L10n.TokenSavedPlaceholder : L10n.TokenRequiredPlaceholder;
        SignOutButton.Visibility = _app.Store.IsConfigured ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnConnect(object sender, RoutedEventArgs e)
    {
        ConnectButton.IsEnabled = false;
        ConnectProgress.IsActive = true;
        ConnectStatus.IsOpen = false;
        try
        {
            var name = await _app.Store.ConnectAsync(ServerBox.Text, TokenBox.Password);
            TokenBox.Password = "";
            ServerBox.Text = Settings.SavedServerUrl;
            ShowStatus(InfoBarSeverity.Success, L10n.ConnectedAs(name));
        }
        catch (Exception error) when (error is ServerAddress.InvalidException or ConnectionException or ApiException
                                          or TokenStoreException or HttpRequestException or TaskCanceledException)
        {
            ShowStatus(InfoBarSeverity.Error, error is HttpRequestException or TaskCanceledException
                ? L10n.CouldntReachServer(error.Message)
                : error.Message);
        }
        finally
        {
            ConnectButton.IsEnabled = true;
            ConnectProgress.IsActive = false;
            UpdateTokenHint();
        }
    }

    private async void OnSignOut(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = L10n.SignOutConfirmTitle,
            Content = L10n.SignOutConfirmMessageWindows,
            PrimaryButtonText = L10n.SignOut,
            CloseButtonText = L10n.Cancel,
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            _app.Store.SignOut();
            TokenBox.Password = "";
            ConnectStatus.IsOpen = false;
        }
        catch (TokenStoreException error)
        {
            ShowStatus(InfoBarSeverity.Error, error.Message);
        }
        UpdateTokenHint();
    }

    private void ShowStatus(InfoBarSeverity severity, string message)
    {
        ConnectStatus.Severity = severity;
        ConnectStatus.Message = message;
        ConnectStatus.IsOpen = true;
    }

    private void OnHideDraftsToggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Settings.HideDrafts = HideDraftsToggle.IsOn;
        _app.Store.FiltersChanged();
    }

    private void OnFilterChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || FilterBox.Text == Settings.RepoFilter) return;
        Settings.RepoFilter = FilterBox.Text;
        _app.Store.FiltersChanged();
    }

    // MARK: About

    private async void OnCheckForUpdates(object sender, RoutedEventArgs e) => await _app.CheckForUpdatesAsync(userInitiated: true);
}
