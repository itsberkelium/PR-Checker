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
            if (Item.IsDraft) badges.Add(new("", "Draft", Secondary));
            if (Item.HasNewCommits) badges.Add(new("", "New commits", Blue));
            if (Item.Reviewers.Count > 0)
                badges.Add(new("", $"{Item.Approvals}/{Item.Reviewers.Count}", Item.Approvals > 0 ? Green : Secondary));
            if (Item.NeedsWork) badges.Add(new("", "Needs work", Orange));
            if (Item.HasConflicts) badges.Add(new("", "Conflicts", Red));
            switch (Item.Build)
            {
                case BuildState.Passed: badges.Add(new("", "Build", Green)); break;
                case BuildState.Failed: badges.Add(new("", "Build", Red)); break;
                case BuildState.Running: badges.Add(new("", "Build", Secondary)); break;
            }
            if (Item.CommentCount > 0) badges.Add(new("", Item.CommentCount.ToString(System.Globalization.CultureInfo.CurrentCulture), Secondary));
            if (Item.OpenTaskCount > 0) badges.Add(new("", Item.OpenTaskCount.ToString(System.Globalization.CultureInfo.CurrentCulture), Orange));
            return badges;
        }
    }

    private static string Label(ReviewStatus status) => status switch
    {
        ReviewStatus.Approved => "Approved",
        ReviewStatus.NeedsWork => "Needs work",
        _ => "Not reviewed",
    };

    public static string Relative(DateTimeOffset date)
    {
        var elapsed = DateTimeOffset.Now - date;
        return elapsed.TotalSeconds < 60 ? "now"
            : elapsed.TotalMinutes < 60 ? Plural((int)elapsed.TotalMinutes, "minute")
            : elapsed.TotalHours < 24 ? Plural((int)elapsed.TotalHours, "hour")
            : elapsed.TotalDays < 2 ? "yesterday"
            : Plural((int)elapsed.TotalDays, "day");

        static string Plural(int value, string unit) => $"{value} {unit}{(value == 1 ? "" : "s")} ago";
    }
}
