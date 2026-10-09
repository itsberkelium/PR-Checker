using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PRChecker.App.Services;
using PRChecker.Core;
using Windows.Graphics;

namespace PRChecker.App.Views;

/// <summary>
/// The one-time Terms of Use agreement on first launch (and after the terms change). The Windows
/// App SDK license requires end users to agree to protective terms; the installer can't show them.
/// </summary>
internal sealed partial class TermsWindow : Window
{
    /// <summary>Bump when TERMS.md changes in a way users must agree to again; keep in sync with macOS.</summary>
    public const int Version = 1;

    private readonly TaskCompletionSource<bool> _result = new();

    private TermsWindow()
    {
        Title = "PR Checker";
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }

        var agree = new Button { Content = L10n.Agree, Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
        var quit = new Button { Content = L10n.Quit };
        var view = new HyperlinkButton { Content = L10n.ViewTerms, Padding = new Thickness(0) };
        agree.Click += (_, _) => Finish(true);
        quit.Click += (_, _) => Finish(false);
        view.Click += (_, _) => Support.Open(Support.TermsOfUse);
        AppWindow.Closing += (_, _) => _result.TrySetResult(false);

        var buttons = new Grid { ColumnSpacing = 8 };
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        buttons.Children.Add(view);
        Grid.SetColumn(quit, 1);
        Grid.SetColumn(agree, 2);
        buttons.Children.Add(quit);
        buttons.Children.Add(agree);

        Content = new StackPanel
        {
            Padding = new Thickness(24),
            Spacing = 16,
            Children =
            {
                new TextBlock { Text = L10n.WelcomeTitle, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] },
                new TextBlock { Text = L10n.TermsPromptWindows, TextWrapping = TextWrapping.Wrap },
                buttons,
            },
        };
        SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop();
    }

    private void Finish(bool agreed)
    {
        _result.TrySetResult(agreed);
        Close();
    }

    /// <summary>Asks if needed; true when the user has agreed to the current terms.</summary>
    public static async Task<bool> EnsureAcceptedAsync(AppSettings settings)
    {
        if (settings.AcceptedTermsVersion >= Version) return true;
        var window = new TermsWindow();
        var scale = window.Content.XamlRoot?.RasterizationScale ?? 1.0;
        window.AppWindow.Resize(new SizeInt32((int)(520 * scale), (int)(240 * scale)));
        CenterOnScreen(window);
        window.Activate();
        var agreed = await window._result.Task;
        if (agreed) settings.AcceptedTermsVersion = Version;
        return agreed;
    }

    private static void CenterOnScreen(Window window)
    {
        var area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var size = window.AppWindow.Size;
        window.AppWindow.Move(new PointInt32(area.X + (area.Width - size.Width) / 2, area.Y + (area.Height - size.Height) / 2));
    }
}
