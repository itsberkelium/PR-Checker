using System.Text.Json;
using System.Text.Json.Serialization;

namespace PRChecker.Core;

// MARK: Bitbucket Server REST payloads

public sealed record Page<T>(IReadOnlyList<T> Values, bool IsLastPage, int? NextPageStart);

public sealed record PullRequest(
    int Id,
    string Title,
    bool? Draft,
    long UpdatedDate,
    PullRequest.Ref FromRef,
    PullRequest.Ref ToRef,
    PullRequest.Participant Author,
    IReadOnlyList<PullRequest.Participant> Reviewers,
    PullRequest.PrProperties? Properties)
{
    public sealed record Ref(string DisplayId, string LatestCommit, Repository Repository);
    public sealed record Repository(string Slug, string Name, Project Project);
    public sealed record Project(string Key);
    public sealed record Participant(User User, ReviewStatus Status, string? LastReviewedCommit);
    public sealed record PrProperties(MergeResult? MergeResult, int? CommentCount, int? OpenTaskCount);
    public sealed record MergeResult(string Outcome);
}

public sealed record User(string Name, string Slug, string? DisplayName)
{
    public bool IsSameUser(string username) =>
        string.Equals(Name, username, StringComparison.OrdinalIgnoreCase)
        || string.Equals(Slug, username, StringComparison.OrdinalIgnoreCase);

    public string Display => DisplayName ?? Name;
}

[JsonConverter(typeof(ReviewStatusConverter))]
public enum ReviewStatus { Unapproved, Approved, NeedsWork }

/// <summary>Unknown statuses count as unapproved.</summary>
internal sealed class ReviewStatusConverter : JsonConverter<ReviewStatus>
{
    public override ReviewStatus Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.GetString() switch
        {
            "APPROVED" => ReviewStatus.Approved,
            "NEEDS_WORK" => ReviewStatus.NeedsWork,
            _ => ReviewStatus.Unapproved,
        };

    public override void Write(Utf8JsonWriter writer, ReviewStatus value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value switch
        {
            ReviewStatus.Approved => "APPROVED",
            ReviewStatus.NeedsWork => "NEEDS_WORK",
            _ => "UNAPPROVED",
        });
}

public sealed record Activity(long Id, long CreatedDate, string Action, string? CommentAction, User User);

public sealed record PullRequestState(string State);

public sealed record BuildStats(int? Successful, int? Failed, int? InProgress);

[JsonConverter(typeof(JsonStringEnumConverter<BuildState>))]
public enum BuildState { None, Running, Passed, Failed }

public static class BuildStates
{
    public static BuildState From(BuildStats stats) =>
        (stats.Failed ?? 0) > 0 ? BuildState.Failed
        : (stats.InProgress ?? 0) > 0 ? BuildState.Running
        : (stats.Successful ?? 0) > 0 ? BuildState.Passed
        : BuildState.None;
}

internal static class Json
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };
}

// MARK: App model

public sealed record Reviewer(string Name, ReviewStatus Status);

/// <summary>A comment or reply by someone else. "New" is decided by <see cref="Created"/>; ids aren't chronological.</summary>
public sealed record Comment(long Id, long Created, string Author);

public sealed record PrItem
{
    /// <summary>Unique across repositories, e.g. "PROJ/web-app#42" (target repository).</summary>
    public required string Id { get; init; }
    public required int Number { get; init; }
    public required string Title { get; init; }
    public required string ProjectKey { get; init; }
    public required string RepoSlug { get; init; }
    public required string RepoName { get; init; }
    public required string SourceBranch { get; init; }
    public required string TargetBranch { get; init; }
    public required string AuthorName { get; init; }
    public required Uri Url { get; init; }
    public required DateTimeOffset Updated { get; init; }
    public required bool IsDraft { get; init; }
    public required string LatestCommit { get; init; }
    public required IReadOnlyList<Reviewer> Reviewers { get; init; }
    public required bool HasConflicts { get; init; }
    public required int CommentCount { get; init; }
    public required int OpenTaskCount { get; init; }
    public BuildState Build { get; init; }
    /// <summary>Review list only: the author pushed commits after my last review.</summary>
    public bool HasNewCommits { get; init; }
    /// <summary>Recent comments by people other than me; null when they couldn't be fetched.</summary>
    public IReadOnlyList<Comment>? CommentsByOthers { get; init; }

    public int Approvals => Reviewers.Count(r => r.Status == ReviewStatus.Approved);
    public bool NeedsWork => Reviewers.Any(r => r.Status == ReviewStatus.NeedsWork);
    /// <summary>Something on my own PR I should act on.</summary>
    public bool NeedsAttention => NeedsWork || HasConflicts || Build == BuildState.Failed || OpenTaskCount > 0;

    /// <summary>The link is built from the configured server, never taken from the API response.</summary>
    public static PrItem From(PullRequest pr, ServerAddress server)
    {
        var repo = pr.ToRef.Repository;
        return new PrItem
        {
            Id = $"{repo.Project.Key}/{repo.Slug}#{pr.Id}",
            Number = pr.Id,
            Title = pr.Title,
            ProjectKey = repo.Project.Key,
            RepoSlug = repo.Slug,
            RepoName = repo.Name,
            SourceBranch = pr.FromRef.DisplayId,
            TargetBranch = pr.ToRef.DisplayId,
            AuthorName = pr.Author.User.Display,
            Url = server.PullRequestUrl(repo.Project.Key, repo.Slug, pr.Id),
            Updated = DateTimeOffset.FromUnixTimeMilliseconds(pr.UpdatedDate),
            IsDraft = pr.Draft ?? false,
            LatestCommit = pr.FromRef.LatestCommit,
            Reviewers = pr.Reviewers.Select(r => new Reviewer(r.User.Display, r.Status)).ToList(),
            HasConflicts = pr.Properties?.MergeResult?.Outcome == "CONFLICTED",
            CommentCount = pr.Properties?.CommentCount ?? 0,
            OpenTaskCount = pr.Properties?.OpenTaskCount ?? 0,
        };
    }

    /// <summary>
    /// A review-list item, or null when the PR doesn't need my attention: not a reviewer,
    /// already approved, or marked needs-work with no new commits since.
    /// </summary>
    public static PrItem? ForReview(PullRequest pr, string username, ServerAddress server)
    {
        var me = pr.Reviewers.FirstOrDefault(r => r.User.IsSameUser(username));
        if (me is null) return null;
        var pushed = me.LastReviewedCommit is not null && me.LastReviewedCommit != pr.FromRef.LatestCommit;
        return me.Status switch
        {
            ReviewStatus.Approved => null,
            ReviewStatus.NeedsWork when !pushed => null,
            _ => From(pr, server) with { HasNewCommits = pushed },
        };
    }
}
