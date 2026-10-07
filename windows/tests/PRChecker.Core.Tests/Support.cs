using System.Collections.Concurrent;
using System.Net;
using System.Text;
using PRChecker.Core;

namespace PRChecker.Core.Tests;

internal sealed class MemoryTokenStore : ITokenStore
{
    public Dictionary<string, string> Items { get; } = [];
    public bool FailWrites { get; set; }

    public string? Read(string account) => Items.GetValueOrDefault(account);

    public void Save(string token, string account)
    {
        if (FailWrites) throw new TokenStoreException("Credential Manager refused the write.");
        Items[account] = token;
    }

    public void Delete(string account)
    {
        if (FailWrites) throw new TokenStoreException("Credential Manager refused the delete.");
        Items.Remove(account);
    }
}

internal sealed class MemoryStore : ISettingsStore, ISnapshotStore
{
    public SettingsData Settings { get; set; } = new();
    public Dictionary<(string Server, string User), Snapshot> Snapshots { get; } = [];

    public SettingsData Load() => Settings;
    public void Save(SettingsData settings) => Settings = settings;
    public Snapshot? Load(string serverId, string username) => Snapshots.GetValueOrDefault((serverId, username.ToLowerInvariant()));
    public void Save(string serverId, string username, Snapshot snapshot) => Snapshots[(serverId, username.ToLowerInvariant())] = snapshot;

    public void DeleteAll(string serverId)
    {
        foreach (var key in Snapshots.Keys.Where(k => k.Server == serverId).ToList()) Snapshots.Remove(key);
    }
}

internal sealed class RecordingNotifier : INotifier
{
    public List<Change> Posted { get; } = [];
    public int Cleared { get; private set; }
    public void Post(Change change, bool showDetails) => Posted.Add(change);
    public void RemoveDelivered() => Cleared++;
}

/// <summary>Stand-in Bitbucket server: answers every request and records host, path and token.</summary>
internal sealed class StubServer : HttpMessageHandler
{
    public sealed record Request(string Host, string PathAndQuery, string? Token);

    public ConcurrentQueue<Request> Requests { get; } = new();
    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Handler { get; set; } =
        (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.InternalServerError));

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Enqueue(new Request(request.RequestUri!.Host, request.RequestUri.PathAndQuery, request.Headers.Authorization?.Parameter));
        return Handler(request, cancellationToken);
    }

    public static HttpResponseMessage Json(string body, string? user = null)
    {
        var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        if (user is not null) response.Headers.Add("X-AUSERNAME", user);
        return response;
    }

    public static HttpResponseMessage Redirect(string location)
    {
        var response = new HttpResponseMessage(HttpStatusCode.Found);
        response.Headers.Location = new Uri(location, UriKind.RelativeOrAbsolute);
        return response;
    }
}

internal static class Fixtures
{
    public static readonly ServerAddress TestServer = ServerAddress.Parse("https://bitbucket.example.com");

    public static string Path(string name) => System.IO.Path.Combine(AppContext.BaseDirectory, "fixtures", name + ".json");

    public static PrItem Item(string status = "UNAPPROVED", string merge = "CLEAN", BuildState build = BuildState.None,
                              IReadOnlyList<Comment>? comments = null) =>
        PrItem.From(MakePr(status, null, "a", merge), TestServer) with { Build = build, CommentsByOthers = comments ?? [] };

    public static PrItem ReviewItem(IReadOnlyList<Comment>? comments = null) =>
        PrItem.ForReview(MakePr("UNAPPROVED", null, "a"), "sam.reviewer", TestServer)! with { CommentsByOthers = comments ?? [] };

    public static PullRequest MakePr(string myStatus, string? lastReviewed, string latest, string merge = "CLEAN", int comments = 3)
    {
        var last = lastReviewed is null ? "null" : $"\"{lastReviewed}\"";
        var json = """
        {
          "id": 2583, "title": "Add date option to payment form", "draft": false, "updatedDate": 1791266000000,
          "fromRef": {"displayId": "feature/payment-date", "latestCommit": "LATEST",
            "repository": {"slug": "web-app", "name": "Web App", "project": {"key": "PROJ"}}},
          "toRef": {"displayId": "test", "latestCommit": "zzz",
            "repository": {"slug": "web-app", "name": "Web App", "project": {"key": "PROJ"}}},
          "author": {"user": {"name": "Alex.Author", "slug": "alex.author", "displayName": "Alex Author"}, "status": "UNAPPROVED"},
          "reviewers": [{"user": {"name": "Sam.Reviewer", "slug": "sam.reviewer", "displayName": "Sam Reviewer"},
            "status": "MY_STATUS", "lastReviewedCommit": LAST}],
          "properties": {"mergeResult": {"outcome": "MERGE"}, "commentCount": COMMENTS, "openTaskCount": 0},
          "links": {"self": [{"href": "file:///etc/passwd"}]}
        }
        """
            .Replace("LATEST", latest, StringComparison.Ordinal)
            .Replace("MY_STATUS", myStatus, StringComparison.Ordinal)
            .Replace("LAST", last, StringComparison.Ordinal)
            .Replace("MERGE", merge, StringComparison.Ordinal)
            .Replace("COMMENTS", comments.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal);
        return System.Text.Json.JsonSerializer.Deserialize<PullRequest>(json, Json.Options)!;
    }
}
