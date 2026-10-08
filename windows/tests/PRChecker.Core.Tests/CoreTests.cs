using System.Net;
using PRChecker.Core;
using static PRChecker.Core.Tests.Fixtures;

namespace PRChecker.Core.Tests;

public sealed class ChangeDetectorTests
{
    private static Snapshot Snap(IEnumerable<PrItem>? review = null, IEnumerable<PrItem>? mine = null, Snapshot? previous = null) =>
        Snapshot.Create(review ?? [], mine ?? [], previous, _ => true);

    [Fact]
    public void Announces_new_review_requests()
    {
        var review = ReviewItem();
        var old = Snap();
        var current = Snap(review: [review], previous: old);
        Assert.Equal(["Review requested by Alex Author"], ChangeDetector.Changes(old, current, [review], []).Select(c => c.Title));
    }

    [Fact]
    public void Announces_status_changes_on_my_PR()
    {
        var before = Item(build: BuildState.Failed, comments: [new(10, 10, "Ali")]);
        var after = Item("APPROVED", "CONFLICTED", BuildState.Passed, [new(12, 12, "Veli"), new(11, 11, "Ali"), new(10, 10, "Ali")]);
        var old = Snap(mine: [before]);
        var current = Snap(mine: [after], previous: old);
        var body = Assert.Single(ChangeDetector.Changes(old, current, [], [after])).Body;

        Assert.Contains("Approved by Sam Reviewer", body, StringComparison.Ordinal);
        Assert.Contains("Merge conflicts", body, StringComparison.Ordinal);
        Assert.Contains("Build fixed", body, StringComparison.Ordinal);
        Assert.Contains("💬 2 new comments from Ali, Veli", body, StringComparison.Ordinal);
    }

    [Fact]
    public void Running_build_keeps_last_result()
    {
        var failed = Snap(mine: [Item(build: BuildState.Failed)]);
        var running = Snap(mine: [Item(build: BuildState.Running)], previous: failed);
        Assert.Equal(BuildState.Failed, running.Mine.Values.Single().SettledBuild);

        var passedItem = Item(build: BuildState.Passed);
        var passed = Snap(mine: [passedItem], previous: running);
        Assert.Equal("✅ Build fixed", Assert.Single(ChangeDetector.Changes(running, passed, [], [passedItem])).Body);
    }

    [Fact]
    public void Announces_new_comments_on_PRs_I_review_by_time_not_id()
    {
        var review = ReviewItem([new(5, 5, "Ali")]);
        var old = Snap(review: [review]);
        // Activity ids aren't chronological: the newer comment has the lower id.
        review = review with { CommentsByOthers = [new(2, 7, "Alex Author"), new(5, 5, "Ali")] };
        var current = Snap(review: [review], previous: old);
        Assert.Equal(["💬 1 new comment from Alex Author"], ChangeDetector.Changes(old, current, [review], []).Select(c => c.Body));
    }

    [Fact]
    public void Announces_merged_PRs()
    {
        var old = Snap(mine: [Item()]);
        var current = Snap(previous: old);
        var changes = ChangeDetector.Changes(old, current, [], [], new Dictionary<string, string> { ["PROJ/web-app#2583"] = "MERGED" });
        Assert.Equal(["🎉 Merged"], changes.Select(c => c.Body));
    }

    [Fact]
    public void Widened_filter_does_not_reannounce()
    {
        var review = ReviewItem();
        var old = Snapshot.Create([review], [], null, _ => false);
        var current = Snap(review: [review], previous: old);
        Assert.Empty(ChangeDetector.Changes(old, current, [review], []));
    }

    [Fact]
    public void Stays_quiet_when_nothing_changed()
    {
        var mine = Item(comments: [new(3, 3, "Ali")]);
        var old = Snap(review: [mine], mine: [mine]);
        var current = Snap(review: [mine], mine: [mine], previous: old);
        Assert.Empty(ChangeDetector.Changes(old, current, [mine], [mine]));
    }

    [Fact]
    public void Snapshots_survive_a_JSON_round_trip()
    {
        var directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            var store = new JsonFileStore(directory);
            var snapshot = Snap(review: [ReviewItem([new(1, 9, "Ali")])], mine: [Item(build: BuildState.Failed)]);
            store.Save("https://a.example.com", "Sam", snapshot);
            var loaded = store.Load("https://a.example.com", "sam")!;
            Assert.Equal(9, loaded.Reviewing.Values.Single().LastCommentDate);
            Assert.Equal(BuildState.Failed, loaded.Mine.Values.Single().SettledBuild);

            store.DeleteAll("https://a.example.com");
            Assert.Null(store.Load("https://a.example.com", "sam"));
        }
        finally { Directory.Delete(directory, recursive: true); }
    }
}

public sealed class FilterTests
{
    [Fact]
    public void Filters_by_project_or_repo()
    {
        var settings = new AppSettings(new MemoryStore(), new MemoryTokenStore());
        var item = Item();
        Assert.True(settings.Includes(item));
        settings.RepoFilter = "proj";
        Assert.True(settings.Includes(item));
        settings.RepoFilter = "OTHER, PROJ/web-app";
        Assert.True(settings.Includes(item));
        settings.RepoFilter = "PROJ/other-repo";
        Assert.False(settings.Includes(item));
    }

    [Fact]
    public void PR_links_ignore_API_links_and_stay_on_the_server()
    {
        Assert.Equal("https://bitbucket.example.com/projects/PROJ/repos/web-app/pull-requests/2583", Item().Url.AbsoluteUri);
        var tricky = TestServer.PullRequestUrl("..", "a/b?c#d", 1);
        Assert.True(TestServer.Owns(tricky));
        Assert.Empty(tricky.Query);
        Assert.Empty(tricky.Fragment);
        Assert.Contains("/projects/", tricky.AbsolutePath, StringComparison.Ordinal);
    }
}

public sealed class TokenHandlingTests
{
    private static readonly ServerAddress ServerA = ServerAddress.Parse("https://a.example.com");
    private static readonly ServerAddress ServerB = ServerAddress.Parse("https://b.example.com");

    private static (AppSettings, MemoryTokenStore) Connected(ServerAddress server, string token)
    {
        var tokens = new MemoryTokenStore();
        var settings = new AppSettings(new MemoryStore(), tokens);
        settings.ApplyConnection(new BitbucketClient(server, token));
        return (settings, tokens);
    }

    [Fact]
    public void Saved_token_is_never_reused_for_another_server()
    {
        var (settings, _) = Connected(ServerA, "token-a");
        Assert.Throws<ConnectionException>(() => settings.DraftClient("https://b.example.com", ""));
        Assert.Equal("token-a", settings.DraftClient("https://a.example.com/", "").Token);
        Assert.Equal("token-b", settings.DraftClient("https://b.example.com", "token-b").Token);
    }

    [Fact]
    public void Tokens_are_scoped_per_server_and_old_ones_removed()
    {
        var (settings, tokens) = Connected(ServerA, "token-a");
        settings.ApplyConnection(new BitbucketClient(ServerB, "token-b"));
        Assert.Equal(new Dictionary<string, string> { [TokenAccounts.For(ServerB)] = "token-b" }, tokens.Items);
        Assert.Equal(ServerB, settings.MakeClient()?.Server);
    }

    [Fact]
    public void Failed_credential_write_changes_nothing()
    {
        var (settings, tokens) = Connected(ServerA, "token-a");
        tokens.FailWrites = true;
        Assert.Throws<TokenStoreException>(() => settings.ApplyConnection(new BitbucketClient(ServerB, "token-b")));
        Assert.Equal(ServerA, settings.Server);
        Assert.Equal("token-a", settings.MakeClient()?.Token);
        Assert.Equal("token-a", tokens.Items[TokenAccounts.For(ServerA)]);
    }

    [Fact]
    public void Settings_file_never_contains_the_token()
    {
        var store = new MemoryStore();
        var settings = new AppSettings(store, new MemoryTokenStore());
        settings.ApplyConnection(new BitbucketClient(ServerA, "secret-token"));
        Assert.DoesNotContain("secret-token", System.Text.Json.JsonSerializer.Serialize(store.Settings), StringComparison.Ordinal);
    }
}

public sealed class NetworkTests : IDisposable
{
    private readonly StubServer _stub = new();

    public void Dispose() => _stub.Dispose();
    private BitbucketClient Client() => new(ServerAddress.Parse("https://a.example.com"), "token-a", _stub);

    [Fact]
    public async Task Stalled_pagination_stops()
    {
        _stub.Handler = (_, _) => Task.FromResult(StubServer.Json("""{"values":[],"isLastPage":false,"nextPageStart":0}"""));
        var error = await Assert.ThrowsAsync<ApiException>(() => Client().DashboardAsync(Role.Reviewer, TestContext.Current.CancellationToken));
        Assert.Equal(ApiErrorKind.PaginationStalled, error.Kind);
        Assert.Single(_stub.Requests);
    }

    [Fact]
    public async Task Endless_pagination_is_capped()
    {
        _stub.Handler = (request, _) =>
        {
            var start = int.Parse(System.Web.HttpUtility.ParseQueryString(request.RequestUri!.Query)["start"]!, System.Globalization.CultureInfo.InvariantCulture);
            return Task.FromResult(StubServer.Json($$"""{"values":[],"isLastPage":false,"nextPageStart":{{start + 100}}}"""));
        };
        var error = await Assert.ThrowsAsync<ApiException>(() => Client().DashboardAsync(Role.Reviewer, TestContext.Current.CancellationToken));
        Assert.Equal(ApiErrorKind.TooManyResults, error.Kind);
        Assert.Equal(BitbucketClient.MaxPages, _stub.Requests.Count);
    }

    [Fact]
    public async Task Oversized_responses_are_rejected_with_or_without_a_length()
    {
        var oversized = new string(' ', BitbucketClient.MaxResponseBytes + 1);
        _stub.Handler = (_, _) => Task.FromResult(StubServer.Json(oversized));
        var withLength = await Assert.ThrowsAsync<ApiException>(() => Client().BuildStateAsync("abc", TestContext.Current.CancellationToken));
        Assert.Equal(ApiErrorKind.ResponseTooLarge, withLength.Kind);

        _stub.Handler = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StreamContent(new MemoryStream(System.Text.Encoding.UTF8.GetBytes(oversized))),
        });
        var streamed = await Assert.ThrowsAsync<ApiException>(() => Client().BuildStateAsync("abc", TestContext.Current.CancellationToken));
        Assert.Equal(ApiErrorKind.ResponseTooLarge, streamed.Kind);
    }

    [Fact]
    public async Task Redirects_to_another_host_are_not_followed()
    {
        _stub.Handler = (request, _) => Task.FromResult(request.RequestUri!.Host == "a.example.com"
            ? StubServer.Redirect("https://evil.example.com/steal")
            : StubServer.Json("""{"successful":1}"""));
        var error = await Assert.ThrowsAsync<ApiException>(() => Client().BuildStateAsync("abc", TestContext.Current.CancellationToken));
        Assert.Equal((ApiErrorKind.Http, 302), (error.Kind, error.StatusCode));
        Assert.All(_stub.Requests, r => Assert.Equal("a.example.com", r.Host));
    }

    [Fact]
    public async Task Redirects_within_the_server_are_followed()
    {
        _stub.Handler = (request, _) => Task.FromResult(request.RequestUri!.AbsolutePath.StartsWith("/moved", StringComparison.Ordinal)
            ? StubServer.Json("""{"failed":1}""")
            : StubServer.Redirect("/moved"));
        Assert.Equal(BuildState.Failed, await Client().BuildStateAsync("abc", TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Redirect_loops_stop()
    {
        _stub.Handler = (_, _) => Task.FromResult(StubServer.Redirect("/again"));
        var error = await Assert.ThrowsAsync<ApiException>(() => Client().BuildStateAsync("abc", TestContext.Current.CancellationToken));
        Assert.Equal(302, error.StatusCode);
        Assert.Equal(BitbucketClient.MaxRedirects + 1, _stub.Requests.Count);
    }

    [Fact]
    public async Task Rate_limiting_is_reported()
    {
        _stub.Handler = (_, _) => Task.FromResult(new HttpResponseMessage((HttpStatusCode)429));
        var error = await Assert.ThrowsAsync<ApiException>(() => Client().BuildStateAsync("abc", TestContext.Current.CancellationToken));
        Assert.Equal(ApiErrorKind.RateLimited, error.Kind);
    }
}

public sealed class ConnectionTests
{
    [Fact]
    public async Task New_server_without_token_sends_nothing()
    {
        var stub = new StubServer();
        var settings = new AppSettings(new MemoryStore(), new MemoryTokenStore()) { HttpHandler = stub };
        settings.ApplyConnection(new BitbucketClient(ServerAddress.Parse("https://a.example.com"), "token-a"));
        using var store = new PrStore(settings, new MemoryStore(), new RecordingNotifier());

        await Assert.ThrowsAsync<ConnectionException>(() => store.ConnectAsync("https://b.example.com", ""));
        Assert.Empty(stub.Requests);
        Assert.Equal("a.example.com", settings.Server?.Host);
    }

    [Fact]
    public async Task Stale_refresh_from_old_server_is_discarded()
    {
        const string empty = """{"values":[],"isLastPage":true}""";
        var stub = new StubServer
        {
            Handler = async (request, cancellation) =>
            {
                if (request.RequestUri!.Host == "a.example.com" && request.RequestUri.AbsolutePath.Contains("dashboard", StringComparison.Ordinal))
                {
                    await Task.Delay(600, cancellation); // still in flight when we switch
                    return StubServer.Json(DashboardWithOnePr, "sam.reviewer");
                }
                return StubServer.Json(empty, "sam.reviewer");
            },
        };
        var snapshots = new MemoryStore();
        var settings = new AppSettings(new MemoryStore(), new MemoryTokenStore()) { HttpHandler = stub, NotificationsEnabled = false };
        settings.ApplyConnection(new BitbucketClient(ServerAddress.Parse("https://a.example.com"), "token-a"));
        using var store = new PrStore(settings, snapshots, new RecordingNotifier());

        var oldRefresh = store.RefreshAsync();
        await Task.Delay(200, TestContext.Current.CancellationToken);
        var name = await store.ConnectAsync("https://b.example.com", "token-b");
        await oldRefresh;
        await Task.Delay(800, TestContext.Current.CancellationToken);

        Assert.Equal("sam.reviewer", name);
        Assert.Empty(store.ReviewItems);
        Assert.Empty(store.MineItems);
        Assert.All(stub.Requests.Where(r => r.Host == "b.example.com"), r => Assert.Equal("token-b", r.Token));
        Assert.All(stub.Requests.Where(r => r.Host == "a.example.com"), r => Assert.Equal("token-a", r.Token));
        Assert.DoesNotContain(snapshots.Snapshots.Keys, k => k.Server.Contains("a.example.com", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Sign_out_clears_token_data_and_notifications()
    {
        var stub = new StubServer { Handler = (_, _) => Task.FromResult(StubServer.Json("""{"values":[],"isLastPage":true}""", "sam.reviewer")) };
        var tokens = new MemoryTokenStore();
        var snapshots = new MemoryStore();
        var notifier = new RecordingNotifier();
        var settings = new AppSettings(new MemoryStore(), tokens) { HttpHandler = stub };
        using var store = new PrStore(settings, snapshots, notifier);
        await store.ConnectAsync("https://a.example.com", "token-a");
        await store.RefreshAsync();
        Assert.NotEmpty(snapshots.Snapshots);

        store.SignOut();
        Assert.Empty(tokens.Items);
        Assert.Empty(snapshots.Snapshots);
        Assert.Equal(1, notifier.Cleared);
        Assert.False(store.IsConfigured);
    }

    [Fact]
    public async Task A_failing_notifier_shows_an_error_instead_of_stopping_refreshes()
    {
        var stub = new StubServer
        {
            Handler = (request, _) => Task.FromResult(request.RequestUri!.AbsolutePath.Contains("dashboard", StringComparison.Ordinal)
                ? StubServer.Json(DashboardWithOnePr, "sam.reviewer")
                : StubServer.Json("""{"values":[],"isLastPage":true}""")),
        };
        var settings = new AppSettings(new MemoryStore(), new MemoryTokenStore()) { HttpHandler = stub };
        settings.ApplyConnection(new BitbucketClient(ServerAddress.Parse("https://a.example.com"), "token-a"));
        var snapshots = new MemoryStore();
        // An earlier snapshot without the PR, so this refresh announces it.
        snapshots.Save("https://a.example.com", "sam.reviewer", new Snapshot());
        using var store = new PrStore(settings, snapshots, new ThrowingNotifier());

        await store.RefreshAsync();
        Assert.StartsWith("Refresh failed", store.ErrorMessage, StringComparison.Ordinal);
        Assert.Single(store.ReviewItems);
    }

    private sealed class ThrowingNotifier : INotifier
    {
        public void Post(Change change, bool showDetails) => throw new InvalidOperationException("Not registered");
        public void RemoveDelivered() => throw new InvalidOperationException("Not registered");
    }

    private const string DashboardWithOnePr = """
    {"values":[{"id":7,"title":"T","updatedDate":0,
      "fromRef":{"displayId":"f","latestCommit":"c","repository":{"slug":"r","name":"R","project":{"key":"P"}}},
      "toRef":{"displayId":"t","latestCommit":"d","repository":{"slug":"r","name":"R","project":{"key":"P"}}},
      "author":{"user":{"name":"x","slug":"x"},"status":"UNAPPROVED"},
      "reviewers":[{"user":{"name":"sam.reviewer","slug":"sam.reviewer"},"status":"UNAPPROVED"}]}],
     "isLastPage":true}
    """;
}
