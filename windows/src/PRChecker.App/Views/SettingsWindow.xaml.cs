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
        foreach (var minutes in AppSettings.RefreshOptions) RefreshBox.Items.Add($"{minutes} min");
        Closed += (_, _) => TokenBox.Password = "";
        Activated += (_, _) => RefreshNotificationState();
        Load();
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
        if (tag == "About")
            LastCheckText.Text = _app.Updates.LastCheck is { } last ? $"Last checked {PrRow.Relative(last)}" : "Checked automatically once a week";
    }

    // MARK: General

    private void RefreshNotificationState()
    {
        var blocked = Settings.NotificationsEnabled && WindowsNotifier.IsBlockedBySystem;
        NotificationsBlocked.IsOpen = blocked;
        TestNotificationButton.Visibility = Settings.NotificationsEnabled && !blocked ? Visibility.Visible : Visibility.Collapsed;
        DetailsToggle.IsEnabled = Settings.NotificationsEnabled;
    }

    private void OnNotificationsToggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Settings.NotificationsEnabled = NotificationsToggle.IsOn;
        if (!NotificationsToggle.IsOn) new WindowsNotifier().RemoveDelivered();
        RefreshNotificationState();
    }

    private void OnDetailsToggled(object sender, RoutedEventArgs e)
    {
        if (!_loading) Settings.NotificationDetails = DetailsToggle.IsOn;
    }

    private void OnSendTest(object sender, RoutedEventArgs e) => WindowsNotifier.SendTest();

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
        TokenBox.PlaceholderText = CanReuseSavedToken ? "Saved – leave empty to keep" : "Required";
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
            ShowStatus(InfoBarSeverity.Success, $"Connected as {name}");
        }
        catch (Exception error) when (error is ServerAddress.InvalidException or ConnectionException or ApiException
                                          or TokenStoreException or HttpRequestException or TaskCanceledException)
        {
            ShowStatus(InfoBarSeverity.Error, error is HttpRequestException or TaskCanceledException
                ? $"Couldn't reach the server: {error.Message}"
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
            Title = "Sign out of Bitbucket?",
            Content = "Removes the access token from Credential Manager and the pull request data PR Checker stored for this server.",
            PrimaryButtonText = "Sign Out",
            CloseButtonText = "Cancel",
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
