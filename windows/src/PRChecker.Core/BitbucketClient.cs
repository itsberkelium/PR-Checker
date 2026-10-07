using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace PRChecker.Core;

public enum ApiErrorKind { Unauthorized, RateLimited, Http, BadResponse, PaginationStalled, TooManyResults, ResponseTooLarge }

public sealed class ApiException(ApiErrorKind kind, int? statusCode = null) : Exception(Describe(kind, statusCode))
{
    public ApiErrorKind Kind { get; } = kind;
    public int? StatusCode { get; } = statusCode;

    private static string Describe(ApiErrorKind kind, int? status) => kind switch
    {
        ApiErrorKind.Unauthorized => "The access token was rejected. Check it in Settings.",
        ApiErrorKind.RateLimited => "Bitbucket is limiting requests. PR Checker will try again later.",
        ApiErrorKind.Http => $"Bitbucket returned HTTP {status}.",
        ApiErrorKind.PaginationStalled => "Bitbucket returned an inconsistent page sequence.",
        ApiErrorKind.TooManyResults => $"More than {BitbucketClient.MaxPages * BitbucketClient.PageSize} open pull requests; narrow it down with filters.",
        ApiErrorKind.ResponseTooLarge => "Bitbucket sent an unexpectedly large response.",
        _ => "Unexpected response from Bitbucket.",
    };
}

public enum Role { Reviewer, Author }

public sealed record Dashboard(IReadOnlyList<PullRequest> PullRequests, string? Username);

/// <summary>
/// Minimal Bitbucket Server / Data Center REST client using an HTTP access token.
/// Limits and redirect rules are described in docs/behavior.md.
/// </summary>
public sealed class BitbucketClient(ServerAddress server, string token, HttpMessageHandler? handler = null)
{
    public const int PageSize = 100;
    public const int MaxPages = 20;
    public const int MaxResponseBytes = 8 * 1024 * 1024;
    public const int MaxRedirects = 5;

    /// <summary>No cookies, no automatic redirects (checked by hand), at most 4 connections.</summary>
    private static readonly HttpClient SharedHttp = Create(new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        UseCookies = false,
        MaxConnectionsPerServer = 4,
        AutomaticDecompression = DecompressionMethods.All,
    });

    private readonly HttpClient _http = handler is null ? SharedHttp : Create(handler);

    public ServerAddress Server { get; } = server;
    public string Token { get; } = token;

    private static HttpClient Create(HttpMessageHandler handler) =>
        new(handler, disposeHandler: false) { Timeout = TimeSpan.FromSeconds(30) };

    public async Task<Dashboard> DashboardAsync(Role role, CancellationToken cancellation = default)
    {
        var prs = new List<PullRequest>();
        string? username = null;
        var start = 0;
        for (var page = 0; page < MaxPages; page++)
        {
            cancellation.ThrowIfCancellationRequested();
            var (body, headers) = await GetAsync(
                $"rest/api/1.0/dashboard/pull-requests?role={(role == Role.Reviewer ? "REVIEWER" : "AUTHOR")}&state=OPEN&limit={PageSize}&start={start}",
                cancellation);
            username ??= Header(headers, "X-AUSERNAME");
            var result = Decode<Page<PullRequest>>(body);
            prs.AddRange(result.Values);
            if (result.IsLastPage || result.NextPageStart is not { } next) return new Dashboard(prs, username);
            if (next <= start) throw new ApiException(ApiErrorKind.PaginationStalled);
            start = next;
        }
        throw new ApiException(ApiErrorKind.TooManyResults);
    }

    /// <summary>The signed-in user name; one small request, used to validate a connection.</summary>
    public async Task<string> CurrentUserAsync(CancellationToken cancellation = default)
    {
        var (_, headers) = await GetAsync("rest/api/1.0/dashboard/pull-requests?limit=1", cancellation);
        return Header(headers, "X-AUSERNAME") is { Length: > 0 } name ? name : await WhoAmIAsync(cancellation);
    }

    public async Task<string> WhoAmIAsync(CancellationToken cancellation = default)
    {
        var (body, _) = await GetAsync("plugins/servlet/applinks/whoami", cancellation);
        var name = System.Text.Encoding.UTF8.GetString(body).Trim();
        if (name.Length is 0 or >= 256 || name.Contains('<')) throw new ApiException(ApiErrorKind.BadResponse);
        return name;
    }

    public async Task<BuildState> BuildStateAsync(string commit, CancellationToken cancellation = default)
    {
        var (body, _) = await GetAsync($"rest/build-status/1.0/commits/stats/{ServerAddress.Segment(commit)}", cancellation);
        return BuildStates.From(Decode<BuildStats>(body));
    }

    /// <summary>Most recent comments and replies on a PR, excluding the given user's own.</summary>
    public async Task<IReadOnlyList<Comment>> CommentsByOthersAsync(PrItem item, string username, CancellationToken cancellation = default)
    {
        var (body, _) = await GetAsync(PullRequestPath(item.ProjectKey, item.RepoSlug, item.Number) + "/activities?limit=50", cancellation);
        return CommentsByOthers(Decode<Page<Activity>>(body).Values, username);
    }

    /// <summary>Added comments and replies, minus the given user's own.</summary>
    public static IReadOnlyList<Comment> CommentsByOthers(IEnumerable<Activity> activities, string username) =>
        activities
            .Where(a => a.Action == "COMMENTED" && a.CommentAction is "ADDED" or "REPLIED")
            .Where(a => !a.User.IsSameUser(username))
            .Select(a => new Comment(a.Id, a.CreatedDate, a.User.Display))
            .ToList();

    /// <summary>"OPEN", "MERGED" or "DECLINED".</summary>
    public async Task<string> StateAsync(string projectKey, string repoSlug, int number, CancellationToken cancellation = default)
    {
        var (body, _) = await GetAsync(PullRequestPath(projectKey, repoSlug, number), cancellation);
        return Decode<PullRequestState>(body).State;
    }

    private static string PullRequestPath(string projectKey, string repoSlug, int number) =>
        $"rest/api/1.0/projects/{ServerAddress.Segment(projectKey)}/repos/{ServerAddress.Segment(repoSlug)}/pull-requests/{number}";

    private static T Decode<T>(byte[] body)
    {
        try { return JsonSerializer.Deserialize<T>(body, Json.Options) ?? throw new ApiException(ApiErrorKind.BadResponse); }
        catch (JsonException) { throw new ApiException(ApiErrorKind.BadResponse); }
    }

    private static string? Header(HttpResponseHeaders headers, string name) =>
        headers.TryGetValues(name, out var values) ? values.FirstOrDefault() : null;

    /// <summary>
    /// GET with redirects followed only within the server, so the Authorization header
    /// can't reach another host; a refused redirect surfaces as its 3xx status.
    /// The body is read in chunks and rejected once it exceeds <see cref="MaxResponseBytes"/>.
    /// </summary>
    private async Task<(byte[] Body, HttpResponseHeaders Headers)> GetAsync(string relativePath, CancellationToken cancellation)
    {
        var url = Server.ApiUrl(relativePath);
        if (!Server.Owns(url)) throw new ApiException(ApiErrorKind.BadResponse);

        for (var hop = 0; ; hop++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Token);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellation);
            var status = (int)response.StatusCode;

            if (status is >= 300 and < 400)
            {
                var location = response.Headers.Location;
                var target = location is null ? null : location.IsAbsoluteUri ? location : new Uri(url, location);
                if (target is null || hop >= MaxRedirects || !Server.Owns(target)) throw new ApiException(ApiErrorKind.Http, status);
                url = target;
                continue;
            }

            switch (status)
            {
                case 401 or 403: throw new ApiException(ApiErrorKind.Unauthorized, status);
                case 429: throw new ApiException(ApiErrorKind.RateLimited, status);
                case < 200 or >= 300: throw new ApiException(ApiErrorKind.Http, status);
            }
            if (response.Content.Headers.ContentLength > MaxResponseBytes) throw new ApiException(ApiErrorKind.ResponseTooLarge);
            return (await ReadCappedAsync(response.Content, cancellation), response.Headers);
        }
    }

    private static async Task<byte[]> ReadCappedAsync(HttpContent content, CancellationToken cancellation)
    {
        await using var stream = await content.ReadAsStreamAsync(cancellation);
        using var buffer = new MemoryStream();
        var chunk = new byte[81920];
        int read;
        while ((read = await stream.ReadAsync(chunk, cancellation)) > 0)
        {
            buffer.Write(chunk, 0, read);
            if (buffer.Length > MaxResponseBytes) throw new ApiException(ApiErrorKind.ResponseTooLarge);
        }
        return buffer.ToArray();
    }
}
