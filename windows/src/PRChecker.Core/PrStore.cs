namespace PRChecker.Core;

/// <summary>Shows notifications. Implemented by the app with Windows notifications.</summary>
public interface INotifier
{
    void Post(Change change, bool showDetails);
    void RemoveDelivered();
}

/// <summary>
/// Polls Bitbucket, keeps the lists and announces changes. Call it from the UI thread: awaits
/// resume there, so property changes reach bindings on the right thread.
/// </summary>
public sealed class PrStore(AppSettings settings, ISnapshotStore snapshots, INotifier notifier) : ObservableObject, IDisposable
{
    /// <summary>Requests in flight at once while fetching comments, builds and PR states.</summary>
    public const int MaxConcurrentRequests = 4;
    /// <summary>Departed PRs looked up per refresh; any beyond this say "No longer open".</summary>
    public const int MaxStateLookups = 10;

    private sealed record CommentCacheEntry(int CommentCount, DateTimeOffset Updated, IReadOnlyList<Comment> Comments);

    private IReadOnlyList<PrItem> _reviewItems = [];
    private IReadOnlyList<PrItem> _mineItems = [];
    private string? _username;
    private DateTimeOffset? _lastUpdated;
    private string? _errorMessage;
    private bool _isLoading;

    private CancellationTokenSource? _pollCancellation;
    private CancellationTokenSource _connectionCancellation = new();
    private Task? _refreshTask;
    /// <summary>Bumped whenever the connection changes; results from older generations are dropped.</summary>
    private int _generation;
    private Dictionary<string, CommentCacheEntry> _commentCache = [];
    /// <summary>Finished build results by commit; running or missing builds are fetched again.</summary>
    private Dictionary<string, BuildState> _buildCache = [];

    public AppSettings Settings { get; } = settings;

    public IReadOnlyList<PrItem> ReviewItems { get => _reviewItems; private set { if (Set(ref _reviewItems, value)) Raise(nameof(ToReview)); } }
    public IReadOnlyList<PrItem> MineItems { get => _mineItems; private set { if (Set(ref _mineItems, value)) Raise(nameof(Mine)); } }
    public string? Username { get => _username; private set => Set(ref _username, value); }
    public DateTimeOffset? LastUpdated { get => _lastUpdated; private set => Set(ref _lastUpdated, value); }
    public string? ErrorMessage { get => _errorMessage; private set => Set(ref _errorMessage, value); }
    public bool IsLoading { get => _isLoading; private set => Set(ref _isLoading, value); }

    public IReadOnlyList<PrItem> ToReview => ReviewItems.Where(Settings.Includes).ToList();
    public IReadOnlyList<PrItem> Mine => MineItems.Where(Settings.Includes).ToList();
    public bool IsConfigured => Settings.MakeClient() is not null;

    /// <summary>Call after a filter changes so bound lists update.</summary>
    public void FiltersChanged()
    {
        Raise(nameof(ToReview));
        Raise(nameof(Mine));
    }

    /// <summary>(Re)starts polling at the configured interval, refreshing immediately.</summary>
    public void Start()
    {
        CancelAndDispose(ref _pollCancellation);
        var cancellation = new CancellationTokenSource();
        _pollCancellation = cancellation;
        _ = PollAsync(cancellation.Token);
    }

    public void Stop() => CancelAndDispose(ref _pollCancellation);

    public void Dispose()
    {
        CancelAndDispose(ref _pollCancellation);
        _connectionCancellation.Cancel();
        _connectionCancellation.Dispose();
    }

    private static void CancelAndDispose(ref CancellationTokenSource? source)
    {
        source?.Cancel();
        source?.Dispose();
        source = null;
    }

    private async Task PollAsync(CancellationToken cancellation)
    {
        while (!cancellation.IsCancellationRequested)
        {
            await RefreshAsync();
            try { await Task.Delay(TimeSpan.FromMinutes(Settings.RefreshMinutes), cancellation); }
            catch (OperationCanceledException) { return; }
        }
    }

    /// <summary>Refreshes, or waits for the refresh already in progress.</summary>
    public async Task RefreshAsync()
    {
        if (_refreshTask is { } running)
        {
            await running;
            return;
        }
        var task = PerformRefreshAsync(_generation, _connectionCancellation.Token);
        _refreshTask = task;
        try { await task; }
        finally { if (_refreshTask == task) _refreshTask = null; }
    }

    /// <summary>
    /// Validates a server and token without saving them; nothing is sent until this runs, and a
    /// blank token only reuses the saved one for the same server. Returns the signed-in user name.
    /// </summary>
    public async Task<string> ConnectAsync(string serverUrl, string token)
    {
        var client = Settings.DraftClient(serverUrl, token);
        var name = await client.CurrentUserAsync();
        Settings.ApplyConnection(client);
        Reset();
        Start();
        return name;
    }

    /// <summary>Removes the token, this connection's stored PR state and its delivered notifications.</summary>
    public void SignOut()
    {
        if (Settings.Server is { } server) snapshots.DeleteAll(server.Id);
        Settings.SignOut();
        Reset();
        notifier.RemoveDelivered();
        ErrorMessage = "Signed out. Connect again in Settings → Bitbucket.";
    }

    /// <summary>Stops in-flight work and forgets everything shown for the previous connection.</summary>
    private void Reset()
    {
        _generation++;
        CancelAndDispose(ref _pollCancellation);
        // Cancel only: an in-flight refresh may still check this token. It has no timer, so GC is enough.
        _connectionCancellation.Cancel();
        _connectionCancellation = new CancellationTokenSource();
        _refreshTask = null;
        ReviewItems = [];
        MineItems = [];
        Username = null;
        LastUpdated = null;
        ErrorMessage = null;
        IsLoading = false;
        _commentCache = [];
        _buildCache = [];
    }

    private bool IsCurrent(int generation, CancellationToken cancellation) =>
        generation == _generation && !cancellation.IsCancellationRequested;

    private async Task PerformRefreshAsync(int generation, CancellationToken cancellation)
    {
        if (Settings.MakeClient() is not { } client)
        {
            ErrorMessage = "Add your server URL and access token in Settings.";
            return;
        }
        IsLoading = true;
        try
        {
            var reviewing = client.DashboardAsync(Role.Reviewer, cancellation);
            var authored = client.DashboardAsync(Role.Author, cancellation);
            var reviewDashboard = await reviewing;
            var authorDashboard = await authored;
            if (!IsCurrent(generation, cancellation)) return;

            var me = reviewDashboard.Username ?? authorDashboard.Username ?? await client.WhoAmIAsync(cancellation);
            if (!IsCurrent(generation, cancellation)) return;

            var server = client.Server;
            var review = reviewDashboard.PullRequests.Select(pr => PrItem.ForReview(pr, me, server)).OfType<PrItem>().ToList();
            var mine = authorDashboard.PullRequests.Select(pr => PrItem.From(pr, server)).ToList();
            var (enrichedReview, enrichedMine, rateLimited) = await EnrichAsync(review, mine, client, me, cancellation);
            if (!IsCurrent(generation, cancellation)) return;

            Username = me;
            ReviewItems = enrichedReview.OrderByDescending(i => i.Updated).ToList();
            MineItems = enrichedMine.OrderByDescending(i => i.Updated).ToList();
            LastUpdated = DateTimeOffset.Now;
            ErrorMessage = rateLimited ? new ApiException(ApiErrorKind.RateLimited).Message : null;
            await NotifyChangesAsync(client, me, generation, cancellation);
        }
        catch (OperationCanceledException) { }
        catch (Exception error) when (error is ApiException or HttpRequestException)
        {
            if (IsCurrent(generation, cancellation)) ErrorMessage = error is ApiException ? error.Message : $"Couldn't reach Bitbucket: {error.Message}";
        }
#pragma warning disable CA1031 // The polling loop must survive anything; the error is shown instead.
        catch (Exception error)
        {
            if (IsCurrent(generation, cancellation)) ErrorMessage = $"Refresh failed: {error.Message}";
        }
#pragma warning restore CA1031
        finally
        {
            if (generation == _generation) IsLoading = false;
        }
    }

    /// <summary>
    /// Adds comments by others to every PR and build results to mine, reusing cached results that
    /// can't have changed. Hidden PRs are included so widening a filter doesn't re-announce them.
    /// </summary>
    private async Task<(List<PrItem> Review, List<PrItem> Mine, bool RateLimited)> EnrichAsync(
        List<PrItem> review, List<PrItem> mine, BitbucketClient client, string me, CancellationToken cancellation)
    {
        var all = review.Concat(mine).ToList();
        var commentJobs = all.Where(item => !(_commentCache.TryGetValue(item.Id, out var cached)
                                              && cached.CommentCount == item.CommentCount && cached.Updated == item.Updated))
                             .ToList();
        var buildJobs = mine.Select(item => item.LatestCommit).Distinct().Where(commit => !_buildCache.ContainsKey(commit)).ToList();
        var rateLimited = false;

        var commentResults = await BoundedAsync(commentJobs, async item =>
        {
            try { return (item, (IReadOnlyList<Comment>?)await client.CommentsByOthersAsync(item, me, cancellation)); }
            catch (ApiException e) when (e.Kind == ApiErrorKind.RateLimited) { rateLimited = true; return (item, null); }
            catch (Exception e) when (e is ApiException or HttpRequestException) { return (item, null); }
        }, cancellation);
        var buildResults = await BoundedAsync(buildJobs, async commit =>
        {
            try { return (commit, (BuildState?)await client.BuildStateAsync(commit, cancellation)); }
            catch (ApiException e) when (e.Kind == ApiErrorKind.RateLimited) { rateLimited = true; return (commit, null); }
            catch (Exception e) when (e is ApiException or HttpRequestException) { return (commit, null); }
        }, cancellation);

        foreach (var (item, comments) in commentResults)
            if (comments is not null) _commentCache[item.Id] = new CommentCacheEntry(item.CommentCount, item.Updated, comments);
        var builds = new Dictionary<string, BuildState>();
        foreach (var (commit, state) in buildResults)
        {
            if (state is not { } value) continue;
            builds[commit] = value;
            if (value is BuildState.Passed or BuildState.Failed) _buildCache[commit] = value;
        }

        // Unknown comments stay null so the snapshot keeps the previous "last seen" time.
        IReadOnlyList<Comment>? CommentsOf(PrItem item) => _commentCache.GetValueOrDefault(item.Id)?.Comments;
        var enrichedReview = review.Select(item => item with { CommentsByOthers = CommentsOf(item) }).ToList();
        var enrichedMine = mine.Select(item => item with
        {
            CommentsByOthers = CommentsOf(item),
            Build = _buildCache.TryGetValue(item.LatestCommit, out var cached) ? cached
                  : builds.TryGetValue(item.LatestCommit, out var fresh) ? fresh : BuildState.None,
        }).ToList();

        var liveIds = all.Select(i => i.Id).ToHashSet();
        _commentCache = _commentCache.Where(e => liveIds.Contains(e.Key)).ToDictionary();
        var liveCommits = mine.Select(i => i.LatestCommit).ToHashSet();
        _buildCache = _buildCache.Where(e => liveCommits.Contains(e.Key)).ToDictionary();
        return (enrichedReview, enrichedMine, rateLimited);
    }

    /// <summary>
    /// Compares against the snapshot saved for this server and user, so restarts and
    /// connection switches don't announce anything that isn't new.
    /// </summary>
    private async Task NotifyChangesAsync(BitbucketClient client, string me, int generation, CancellationToken cancellation)
    {
        var old = snapshots.Load(client.Server.Id, me);
        var current = Snapshot.Create(ReviewItems, MineItems, old, Settings.Includes);
        snapshots.Save(client.Server.Id, me, current);
        if (!Settings.NotificationsEnabled || old is null) return;

        var departed = old.DepartedMine(current).Take(MaxStateLookups).ToList();
        var states = await BoundedAsync(departed, async entry =>
        {
            try { return (entry.Key, (string?)await client.StateAsync(entry.Value.ProjectKey, entry.Value.RepoSlug, entry.Value.Number, cancellation)); }
            catch (Exception e) when (e is ApiException or HttpRequestException) { return (entry.Key, null); }
        }, cancellation);
        if (!IsCurrent(generation, cancellation)) return;

        var closedStates = states.Where(s => s.Item2 is not null).ToDictionary(s => s.Key, s => s.Item2!);
        foreach (var change in ChangeDetector.Changes(old, current, ToReview, Mine, closedStates))
            notifier.Post(change, Settings.NotificationDetails);
    }

    /// <summary>Runs <paramref name="operation"/> over the inputs with at most <see cref="MaxConcurrentRequests"/> in flight.</summary>
    private static async Task<IReadOnlyList<TOutput>> BoundedAsync<TInput, TOutput>(
        IReadOnlyList<TInput> inputs, Func<TInput, Task<TOutput>> operation, CancellationToken cancellation)
    {
        using var gate = new SemaphoreSlim(MaxConcurrentRequests);
        var tasks = inputs.Select(async input =>
        {
            await gate.WaitAsync(cancellation);
            try { return await operation(input); }
            finally { gate.Release(); }
        });
        return await Task.WhenAll(tasks);
    }

#if DEBUG
    /// <summary>Shows the given PRs without any network access; for screenshots.</summary>
    public void ShowDemoData(IReadOnlyList<PrItem> review, IReadOnlyList<PrItem> mine, string username)
    {
        Reset();
        ReviewItems = review;
        MineItems = mine;
        Username = username;
        LastUpdated = DateTimeOffset.Now.AddSeconds(-40);
    }
#endif
}
