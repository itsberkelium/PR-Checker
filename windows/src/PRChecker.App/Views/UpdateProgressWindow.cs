using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PRChecker.Core;
using Windows.Graphics;

namespace PRChecker.App.Views;

/// <summary>
/// Shown from "Yes, install" until the app quits to apply the update, so an update never runs
/// without visible progress.
/// </summary>
internal sealed partial class UpdateProgressWindow : Window
{
    private readonly TextBlock _status = new();
    private readonly ProgressBar _bar = new() { Minimum = 0, Maximum = 100 };
    private bool _canClose;

    public UpdateProgressWindow()
    {
        Title = L10n.UpdatingTitle;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.IsAlwaysOnTop = true;
        }
        // Closing it wouldn't stop the update; keep it until the app restarts.
        AppWindow.Closing += (_, args) => args.Cancel = !_canClose;

        Content = new StackPanel
        {
            Padding = new Thickness(24),
            Spacing = 12,
            Children =
            {
                new TextBlock { Text = L10n.UpdatingTitle, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] },
                _status,
                _bar,
                new TextBlock
                {
                    Text = L10n.RestartAfterUpdate,
                    TextWrapping = TextWrapping.Wrap,
                    Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
                },
            },
        };
        SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop();
        Report(0);
    }

    public void ShowCentered()
    {
        var scale = Content.XamlRoot?.RasterizationScale ?? 1.0;
        AppWindow.Resize(new SizeInt32((int)(440 * scale), (int)(200 * scale)));
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var size = AppWindow.Size;
        AppWindow.Move(new PointInt32(area.X + (area.Width - size.Width) / 2, area.Y + (area.Height - size.Height) / 2));
        Activate();
    }

    /// <summary>Call on the UI thread.</summary>
    public void Report(int percent)
    {
        _status.Text = L10n.DownloadingUpdate(percent);
        _bar.Value = percent;
    }

    /// <summary>Download failed: let the window go.</summary>
    public void Dismiss()
    {
        _canClose = true;
        Close();
    }
}
