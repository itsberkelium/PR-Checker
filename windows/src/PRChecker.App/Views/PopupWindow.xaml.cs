using System.ComponentModel;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PRChecker.App.Services;
using PRChecker.Core;
using Windows.Graphics;

namespace PRChecker.App.Views;

/// <summary>The PR list, shown above the tray like a flyout and hidden when it loses focus.</summary>
public sealed partial class PopupWindow : Window
{
    private const int WidthDips = 420;
    private const int HeightDips = 520;
    private const int MarginDips = 12;

    private readonly App _app;
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(30) };

    internal PopupWindow(App app)
    {
        _app = app;
        InitializeComponent();

        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        AppWindow.IsShownInSwitchers = false;
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsAlwaysOnTop = true;
            presenter.SetBorderAndTitleBar(hasBorder: true, hasTitleBar: false);
        }
        AppWindow.Closing += (_, args) => { args.Cancel = true; HideWindow(); };
        Activated += (_, args) => { if (args.WindowActivationState == WindowActivationState.Deactivated) HideWindow(); };

        _app.Store.PropertyChanged += OnStoreChanged;
        _clock.Tick += (_, _) => Render();
        Render();
    }

    internal bool IsShown => AppWindow.IsVisible;

    /// <summary>Bottom-right of the work area, i.e. next to the tray on a default taskbar.</summary>
    internal void ShowNearTray()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var scale = Content.XamlRoot?.RasterizationScale ?? 1.0;
        int Px(int dips) => (int)Math.Round(dips * scale);
        AppWindow.MoveAndResize(new RectInt32(
            area.X + area.Width - Px(WidthDips + MarginDips),
            area.Y + area.Height - Px(HeightDips + MarginDips),
            Px(WidthDips), Px(HeightDips)));

        Render();
        AppWindow.Show();
        Activate();
        _clock.Start();

        // Opening the list with stale data triggers a refresh.
        if (_app.Store.IsConfigured && (_app.Store.LastUpdated is not { } last || DateTimeOffset.Now - last > TimeSpan.FromSeconds(60)))
            _ = _app.Store.RefreshAsync();
    }

    internal void HideWindow()
    {
        _clock.Stop();
        AppWindow.Hide();
    }

    private void OnStoreChanged(object? sender, PropertyChangedEventArgs e) => Render();
    private void OnTabChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args) => Render();

    private void Render()
    {
        var store = _app.Store;
        var review = Tabs.SelectedItem != MineTab;
        var items = review ? store.ToReview : store.Mine;
        ReviewTab.Text = $"To review ({store.ToReview.Count})";
        MineTab.Text = $"Mine ({store.Mine.Count})";

        List.ItemsSource = items.Select(item => new PrRow(item, showsAuthor: review)).ToList();
        var empty = items.Count == 0;
        List.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        EmptyState.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        EmptyAction.Visibility = Visibility.Collapsed;
        if (empty)
        {
            if (store.ErrorMessage is { } error)
            {
                EmptyIcon.Glyph = "";
                EmptyText.Text = error;
                EmptyAction.Visibility = Visibility.Visible;
            }
            else if (store.LastUpdated is null)
            {
                EmptyIcon.Glyph = "";
                EmptyText.Text = "Loading…";
            }
            else
            {
                EmptyIcon.Glyph = review ? "" : "";
                EmptyText.Text = review ? "Nothing to review" : "No open pull requests";
            }
        }

        ErrorIcon.Visibility = store.ErrorMessage is not null && !empty ? Visibility.Visible : Visibility.Collapsed;
        ToolTipService.SetToolTip(ErrorIcon, store.ErrorMessage);
        UpdatedText.Text = store.LastUpdated is { } updated ? $"Updated {PrRow.Relative(updated)}" : "";
        RefreshButton.IsEnabled = !store.IsLoading;
        var notifier = _app.Notifier;
        NotificationsBlocked.Title = notifier.IsAvailable ? "Notifications are off in Windows Settings" : "Notifications aren't available on this PC";
        NotificationsBlocked.ActionButton.Visibility = notifier.IsAvailable ? Visibility.Visible : Visibility.Collapsed;
        NotificationsBlocked.IsOpen = store.Settings.NotificationsEnabled && (notifier.IsBlockedBySystem || !notifier.IsAvailable);
    }

    private void OnItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is PrRow row) Platform.OpenLink(row.Item.Url.AbsoluteUri, _app.Store.Settings);
    }

    private void OnRefresh(object sender, RoutedEventArgs e) => _ = _app.Store.RefreshAsync();

    private void OnSettings(object sender, RoutedEventArgs e)
    {
        HideWindow();
        _app.ShowSettings(_app.Store.IsConfigured ? SettingsWindow.Page.General : SettingsWindow.Page.Bitbucket);
    }

    private void OnQuit(object sender, RoutedEventArgs e) => _app.Quit();

    private void OnOpenNotificationSettings(object sender, RoutedEventArgs e) => Platform.OpenNotificationSettings();
}
