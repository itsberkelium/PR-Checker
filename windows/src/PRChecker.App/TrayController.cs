using System.ComponentModel;
using System.Windows.Input;
using H.NotifyIcon;
using H.NotifyIcon.Core;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using PRChecker.App.Views;
using PRChecker.Core;

namespace PRChecker.App;

/// <summary>
/// The tray icon: the app icon when nothing waits, otherwise the number of PRs to review
/// (orange when one of my PRs needs attention). Left click toggles the list; right click has a menu.
/// </summary>
internal sealed partial class TrayController(App app) : IDisposable
{
    private readonly TaskbarIcon _icon = new();
    private readonly ImageSource _appIcon = new BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico")));
    private readonly MenuFlyoutItem _showItem = new();
    private readonly MenuFlyoutItem _refreshItem = new();
    private readonly MenuFlyoutItem _settingsItem = new();
    private readonly MenuFlyoutItem _quitItem = new();

    public void Create()
    {
        _icon.LeftClickCommand = new Command(app.TogglePopup);
        _icon.NoLeftClickDelay = true;
        _icon.ContextMenuMode = ContextMenuMode.PopupMenu;
        _showItem.Command = new Command(app.ShowPopup);
        _refreshItem.Command = new Command(() => _ = app.Store.RefreshAsync());
        _settingsItem.Command = new Command(() => app.ShowSettings());
        _quitItem.Command = new Command(app.Quit);
        _icon.ContextFlyout = new MenuFlyout
        {
            Items = { _showItem, _refreshItem, _settingsItem, new MenuFlyoutSeparator(), _quitItem },
        };
        app.Store.PropertyChanged += OnStoreChanged;
        Localizer.Changed += OnLanguageChanged;
        Update();
        _icon.ForceCreate(enablesEfficiencyMode: false);
    }

    private void OnStoreChanged(object? sender, PropertyChangedEventArgs e) => Update();

    private void OnLanguageChanged() => _icon.DispatcherQueue.TryEnqueue(Update);

    private void Update()
    {
        var store = app.Store;
        var count = store.ToReview.Count;
        var attention = store.Mine.Any(i => i.NeedsAttention);

        _showItem.Text = L10n.ShowPullRequests;
        _refreshItem.Text = L10n.Refresh;
        _settingsItem.Text = L10n.Settings;
        _quitItem.Text = L10n.QuitApp;
        _icon.ToolTipText = store.IsConfigured
            ? L10n.TrayToReview(count) + (attention ? L10n.TrayAttention : "")
            : L10n.TrayNotConnected;

        _icon.IconSource = count == 0 && !attention
            ? _appIcon
            : new GeneratedIconSource
            {
                Text = count > 99 ? "99+" : count.ToString(System.Globalization.CultureInfo.InvariantCulture),
                Foreground = new SolidColorBrush(Colors.White),
                Background = new SolidColorBrush(attention ? Colors.DarkOrange : Colors.RoyalBlue),
                FontWeight = FontWeights.Bold,
                FontSize = count > 9 ? 44 : 56,
            };
    }

    public void Dispose()
    {
        app.Store.PropertyChanged -= OnStoreChanged;
        Localizer.Changed -= OnLanguageChanged;
        _icon.Dispose();
    }

    // Partial so the WinRT source generator can make it usable from XAML under Native AOT.
    private sealed partial class Command(Action action) : ICommand
    {
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => action();
    }
}
