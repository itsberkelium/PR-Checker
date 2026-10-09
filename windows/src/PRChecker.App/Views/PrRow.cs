using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using PRChecker.Core;
using Windows.UI;

namespace PRChecker.App.Views;

// Partial so the WinRT source generator can project them into XAML lists under Native AOT.
public sealed partial record Badge(string Glyph, string Text, Brush Foreground);

/// <summary>Display strings and badges for one PR, same as the macOS row.</summary>
public sealed partial class PrRow(PrItem item, bool showsAuthor)
{
    private static SolidColorBrush Brush(Color color) => new(color);
    private static readonly Brush Green = Brush(Color.FromArgb(255, 16, 137, 62));
    private static readonly Brush Red = Brush(Color.FromArgb(255, 196, 43, 28));
    private static readonly Brush Orange = Brush(Color.FromArgb(255, 202, 80, 16));
    private static readonly Brush Blue = Brush(Color.FromArgb(255, 0, 103, 192));
    private static Brush Secondary => (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];

    internal PrItem Item { get; } = item;
    public string Title => Item.Title;
    public string Updated => Relative(Item.Updated);
    public string Subtitle =>
        $"{Item.RepoName} #{Item.Number} · {(showsAuthor ? Item.AuthorName + " · " : "")}{Item.SourceBranch} → {Item.TargetBranch}";
    public string Tooltip => string.Join("\n", Item.Reviewers.Select(r => $"{r.Name}: {Label(r.Status)}"));

    public IReadOnlyList<Badge> Badges
    {
        get
        {
            var badges = new List<Badge>();
            if (Item.IsDraft) badges.Add(new("", L10n.BadgeDraft, Secondary));
            if (Item.HasNewCommits) badges.Add(new("", L10n.BadgeNewCommits, Blue));
            if (Item.Reviewers.Count > 0)
                badges.Add(new("", $"{Item.Approvals}/{Item.Reviewers.Count}", Item.Approvals > 0 ? Green : Secondary));
            if (Item.NeedsWork) badges.Add(new("", L10n.NeedsWork, Orange));
            if (Item.HasConflicts) badges.Add(new("", L10n.BadgeConflicts, Red));
            switch (Item.Build)
            {
                case BuildState.Passed: badges.Add(new("", L10n.BadgeBuild, Green)); break;
                case BuildState.Failed: badges.Add(new("", L10n.BadgeBuild, Red)); break;
                case BuildState.Running: badges.Add(new("", L10n.BadgeBuild, Secondary)); break;
            }
            if (Item.CommentCount > 0) badges.Add(new("", Item.CommentCount.ToString(Localizer.Culture), Secondary));
            if (Item.OpenTaskCount > 0) badges.Add(new("", Item.OpenTaskCount.ToString(Localizer.Culture), Orange));
            return badges;
        }
    }

    private static string Label(ReviewStatus status) => status switch
    {
        ReviewStatus.Approved => L10n.ReviewerApproved,
        ReviewStatus.NeedsWork => L10n.NeedsWork,
        _ => L10n.ReviewerNotReviewed,
    };

    public static string Relative(DateTimeOffset date)
    {
        var elapsed = DateTimeOffset.Now - date;
        return elapsed.TotalSeconds < 60 ? L10n.RelativeNow
            : elapsed.TotalMinutes < 60 ? L10n.RelativeMinutes((int)elapsed.TotalMinutes)
            : elapsed.TotalHours < 24 ? L10n.RelativeHours((int)elapsed.TotalHours)
            : elapsed.TotalDays < 2 ? L10n.RelativeYesterday
            : L10n.RelativeDays((int)elapsed.TotalDays);
    }
}
