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

namespace PRChecker.App;

/// <summary>
/// The tray icon: the app icon when nothing waits, otherwise the number of PRs to review
/// (orange when one of my PRs needs attention). Left click toggles the list; right click has a menu.
/// </summary>
internal sealed partial class TrayController(App app) : IDisposable
{
    private readonly TaskbarIcon _icon = new();
    private readonly ImageSource _appIcon = new BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico")));

    public void Create()
    {
        _icon.LeftClickCommand = new Command(app.TogglePopup);
        _icon.NoLeftClickDelay = true;
        _icon.ContextMenuMode = ContextMenuMode.PopupMenu;
        _icon.ContextFlyout = new MenuFlyout
        {
            Items =
            {
                Item("Show Pull Requests", app.ShowPopup),
                Item("Refresh", () => _ = app.Store.RefreshAsync()),
                Item("Settings", () => app.ShowSettings()),
                new MenuFlyoutSeparator(),
                Item("Quit PR Checker", app.Quit),
            },
        };
        app.Store.PropertyChanged += OnStoreChanged;
        Update();
        _icon.ForceCreate(enablesEfficiencyMode: false);
    }

    private static MenuFlyoutItem Item(string text, Action action) => new() { Text = text, Command = new Command(action) };

    private void OnStoreChanged(object? sender, PropertyChangedEventArgs e) => Update();

    private void Update()
    {
        var store = app.Store;
        var count = store.ToReview.Count;
        var attention = store.Mine.Any(i => i.NeedsAttention);

        _icon.ToolTipText = store.IsConfigured
            ? $"PR Checker – {count} to review{(attention ? ", one of yours needs attention" : "")}"
            : "PR Checker – not connected";

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
