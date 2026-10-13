namespace PRChecker.Core;

/// <summary>
/// What the app needs from a code host. Each provider turns its own API payloads into
/// <see cref="PrItem"/>s, so the store, notifications and views don't depend on any one host.
/// Bitbucket Server / Data Center (<see cref="BitbucketClient"/>) is the only provider so far.
/// </summary>
public interface IPrProvider
{
    ServerAddress Server { get; }
    string Token { get; }

    /// <summary>The signed-in user name; one small request, used to validate a connection.</summary>
    Task<string> CurrentUserAsync(CancellationToken cancellation = default);

    /// <summary>
    /// Open PRs waiting for my review and my own open PRs, with the signed-in user name.
    /// Review PRs I've already handled are left out (see "Review list" in docs/behavior.md).
    /// </summary>
    Task<OpenPullRequests> OpenPullRequestsAsync(CancellationToken cancellation = default);

    /// <summary>My recently merged PRs, most recently merged first, each with <see cref="PrItem.Merged"/> set.</summary>
    Task<IReadOnlyList<PrItem>> RecentlyMergedAsync(CancellationToken cancellation = default);

    /// <summary>Recent comments and replies on a PR, excluding the given user's own.</summary>
    Task<IReadOnlyList<Comment>> CommentsByOthersAsync(PrItem item, string username, CancellationToken cancellation = default);

    /// <summary>Combined build result of a commit.</summary>
    Task<BuildState> BuildStateAsync(string commit, CancellationToken cancellation = default);

    /// <summary>"OPEN", "MERGED" or "DECLINED", for a PR that left my list.</summary>
    Task<string> StateAsync(string projectKey, string repoSlug, int number, CancellationToken cancellation = default);
}

public sealed record OpenPullRequests(IReadOnlyList<PrItem> ToReview, IReadOnlyList<PrItem> Mine, string Username);
