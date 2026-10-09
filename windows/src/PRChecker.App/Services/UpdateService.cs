using Velopack;
using Velopack.Sources;

namespace PRChecker.App.Services;

/// <summary>
/// Velopack updates from the same CDN as the Mac app. Checks once a week and asks before
/// installing. Packages are downloaded over HTTPS and verified against the hashes in the feed;
/// they aren't code-signed yet. Always downloads the full package: rebuilding a delta update
/// on the user's PC took minutes with no way to show meaningful progress.
/// </summary>
internal sealed class UpdateService
{
    public const string FeedUrl = "https://gu-cdn.berke.dev/pr-checker/windows/";
    private static readonly TimeSpan Interval = TimeSpan.FromDays(7);

    private readonly UpdateManager _manager =
        new(new SimpleWebSource(FeedUrl), new UpdateOptions { MaximumDeltasBeforeFallback = -1 });
    private readonly string _stateFile = Path.Combine(Platform.DataDirectory, "last-update-check");

    /// <summary>False for development builds that weren't installed by Velopack.</summary>
    public bool IsInstalled => _manager.IsInstalled;

    public DateTimeOffset? LastCheck
    {
        get => File.Exists(_stateFile) && DateTimeOffset.TryParse(File.ReadAllText(_stateFile), out var date) ? date : null;
        private set
        {
            Directory.CreateDirectory(Platform.DataDirectory);
            File.WriteAllText(_stateFile, value?.ToString("O"));
        }
    }

    public bool IsDue => LastCheck is not { } last || DateTimeOffset.Now - last >= Interval;

    /// <summary>The newer version, or null when up to date or not installed.</summary>
    public async Task<UpdateInfo?> CheckAsync()
    {
        if (!IsInstalled) return null;
        Log.Info("Checking for updates");
        var update = await _manager.CheckForUpdatesAsync();
        Log.Info(update is null ? "Up to date" : $"Update available: {update.TargetFullRelease.Version}");
        LastCheck = DateTimeOffset.Now;
        return update;
    }

    /// <summary>Downloads (reporting 0–100 on a background thread), then quits to apply and restart.</summary>
    public async Task InstallAndRestartAsync(UpdateInfo update, Action<int> progress)
    {
        var started = DateTimeOffset.Now;
        Log.Info($"Downloading update {update.TargetFullRelease.Version}");
        await _manager.DownloadUpdatesAsync(update, progress);
        Log.Info($"Downloaded in {(DateTimeOffset.Now - started).TotalSeconds:0.0} s; applying and restarting");
        _manager.ApplyUpdatesAndRestart(update);
    }
}
