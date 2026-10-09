namespace PRChecker.Core;

/// <summary>
/// What we remember between refreshes to decide what's worth a notification. Covers every
/// open PR, not just the ones the filters show, so changing a filter never makes old PRs look new.
/// </summary>
public sealed record Snapshot
{
    public sealed record ReviewingState(long LastCommentDate);

    public sealed record MineState(
        string Title,
        string Url,
        string ProjectKey,
        string RepoSlug,
        int Number,
        /* Whether the filters showed it; departures of hidden PRs aren't announced. */
        bool Shown,
        IReadOnlyList<string> ApprovedBy,
        IReadOnlyList<string> NeedsWorkBy,
        bool Conflicted,
        /* Last finished build result; a running build keeps the previous one. */
        BuildState SettledBuild,
        long LastCommentDate);

    public Dictionary<string, ReviewingState> Reviewing { get; init; } = [];
    public Dictionary<string, MineState> Mine { get; init; } = [];

    public static Snapshot Create(IEnumerable<PrItem> toReview, IEnumerable<PrItem> mine, Snapshot? previous, Func<PrItem, bool> isShown)
    {
        var snapshot = new Snapshot();
        foreach (var item in toReview)
        {
            var before = previous?.Reviewing.GetValueOrDefault(item.Id)?.LastCommentDate;
            snapshot.Reviewing[item.Id] = new ReviewingState(LastCommentDate(item, before));
        }
        foreach (var item in mine)
        {
            var before = previous?.Mine.GetValueOrDefault(item.Id);
            snapshot.Mine[item.Id] = new MineState(
                item.Title,
                item.Url.AbsoluteUri,
                item.ProjectKey,
                item.RepoSlug,
                item.Number,
                isShown(item),
                item.Reviewers.Where(r => r.Status == ReviewStatus.Approved).Select(r => r.Name).Distinct().Order(StringComparer.Ordinal).ToList(),
                item.Reviewers.Where(r => r.Status == ReviewStatus.NeedsWork).Select(r => r.Name).Distinct().Order(StringComparer.Ordinal).ToList(),
                item.HasConflicts,
                item.Build == BuildState.Running ? before?.SettledBuild ?? BuildState.None : item.Build,
                LastCommentDate(item, before?.LastCommentDate));
        }
        return snapshot;
    }

    /// <summary>Open PRs of mine that were shown last time and are gone now.</summary>
    public IEnumerable<KeyValuePair<string, MineState>> DepartedMine(Snapshot current) =>
        Mine.Where(entry => entry.Value.Shown && !current.Mine.ContainsKey(entry.Key))
            .OrderBy(entry => entry.Key, StringComparer.Ordinal);

    private static long LastCommentDate(PrItem item, long? before)
    {
        var latest = item.CommentsByOthers is { Count: > 0 } comments ? comments.Max(c => c.Created) : 0;
        return Math.Max(latest, before ?? 0);
    }
}

public sealed record Change(string Title, string Body, Uri Url);

public static class ChangeDetector
{
    /// <summary>
    /// One change per PR that's new to review or whose state changed. <paramref name="toReview"/> and
    /// <paramref name="mine"/> are the filtered lists; only those get announced.
    /// <paramref name="closedStates"/> maps departed PR ids to "MERGED"/"DECLINED" when known.
    /// </summary>
    public static IReadOnlyList<Change> Changes(
        Snapshot old, Snapshot current, IEnumerable<PrItem> toReview, IEnumerable<PrItem> mine,
        IReadOnlyDictionary<string, string>? closedStates = null)
    {
        var changes = new List<Change>();

        foreach (var item in toReview)
        {
            if (!old.Reviewing.TryGetValue(item.Id, out var before))
            {
                var title = item.HasNewCommits ? L10n.NotifyNewCommits : L10n.NotifyReviewRequested(item.AuthorName);
                changes.Add(new Change(title, item.Title, item.Url));
                continue;
            }
            if (CommentLine(item, before.LastCommentDate) is { } line) changes.Add(new Change(item.Title, line, item.Url));
        }

        foreach (var item in mine)
        {
            if (!old.Mine.TryGetValue(item.Id, out var before) || !current.Mine.TryGetValue(item.Id, out var after)) continue;
            var lines = new List<string>();
            lines.AddRange(after.ApprovedBy.Except(before.ApprovedBy).Order(StringComparer.Ordinal).Select(L10n.NotifyApproved));
            lines.AddRange(after.NeedsWorkBy.Except(before.NeedsWorkBy).Order(StringComparer.Ordinal).Select(L10n.NotifyNeedsWork));
            if (after.Conflicted != before.Conflicted) lines.Add(after.Conflicted ? L10n.NotifyConflicts : L10n.NotifyConflictsResolved);
            if (after.SettledBuild != before.SettledBuild)
            {
                if (after.SettledBuild == BuildState.Failed) lines.Add(L10n.NotifyBuildFailed);
                if (after.SettledBuild == BuildState.Passed && before.SettledBuild == BuildState.Failed) lines.Add(L10n.NotifyBuildFixed);
            }
            if (CommentLine(item, before.LastCommentDate) is { } line) lines.Add(line);
            if (lines.Count > 0) changes.Add(new Change(item.Title, string.Join("\n", lines), item.Url));
        }

        foreach (var (id, state) in old.DepartedMine(current))
        {
            var body = closedStates?.GetValueOrDefault(id) switch
            {
                "MERGED" => L10n.NotifyMerged,
                "DECLINED" => L10n.NotifyDeclined,
                _ => L10n.NotifyNoLongerOpen,
            };
            changes.Add(new Change(state.Title, body, new Uri(state.Url)));
        }
        return changes;
    }

    private static string? CommentLine(PrItem item, long lastSeen)
    {
        var fresh = (item.CommentsByOthers ?? []).Where(c => c.Created > lastSeen).OrderBy(c => c.Created).ToList();
        if (fresh.Count == 0) return null;
        var authors = fresh.Select(c => c.Author).Distinct().ToList();
        return L10n.NotifyComments(fresh.Count, string.Join(", ", authors));
    }
}
