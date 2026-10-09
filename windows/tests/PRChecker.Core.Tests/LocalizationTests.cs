using System.Globalization;
using System.Runtime.CompilerServices;
using PRChecker.Core;
using static PRChecker.Core.Tests.Fixtures;

namespace PRChecker.Core.Tests;

internal static class EnglishByDefault
{
    /// <summary>Tests assert English text, whatever the language of the machine running them.</summary>
    [ModuleInitializer]
    internal static void Initialize()
    {
        Localizer.SystemCulture = CultureInfo.GetCultureInfo("en-US");
        Localizer.Apply(LanguagePreference.English);
    }
}

[CollectionDefinition(nameof(LanguageSwitching), DisableParallelization = true)]
public sealed class LanguageSwitching;

/// <summary>Switches the global language, so it runs apart from the other tests.</summary>
[Collection(nameof(LanguageSwitching))]
public sealed class LocalizationTests : IDisposable
{
    public void Dispose()
    {
        Localizer.SystemCulture = CultureInfo.GetCultureInfo("en-US");
        Localizer.Apply(LanguagePreference.English);
    }

    [Fact]
    public void System_preference_follows_the_OS_language()
    {
        Localizer.SystemCulture = CultureInfo.GetCultureInfo("tr-TR");
        Assert.Equal(AppLanguage.Turkish, Localizer.Resolve(LanguagePreference.System));
        Localizer.SystemCulture = CultureInfo.GetCultureInfo("de-DE");
        Assert.Equal(AppLanguage.English, Localizer.Resolve(LanguagePreference.System));
        Assert.Equal(AppLanguage.Turkish, Localizer.Resolve(LanguagePreference.Turkish));
        Assert.Equal(AppLanguage.English, Localizer.Resolve(LanguagePreference.English));
    }

    [Fact]
    public void Changing_the_setting_switches_immediately_and_is_saved()
    {
        var store = new MemoryStore();
        var settings = new AppSettings(store, new MemoryTokenStore());
        var changes = 0;
        Localizer.Changed += Count;
        try
        {
            settings.Language = LanguagePreference.Turkish;
            Assert.Equal(AppLanguage.Turkish, Localizer.Language);
            Assert.Equal("İncelenecek bir şey yok", L10n.NothingToReview);
            Assert.Equal(LanguagePreference.Turkish, store.Settings.Language);
            Assert.Equal(1, changes);
        }
        finally { Localizer.Changed -= Count; }

        void Count() => changes++;
    }

    [Fact]
    public void Notifications_are_written_in_the_chosen_language()
    {
        Localizer.Apply(LanguagePreference.Turkish);
        var before = Item(build: BuildState.Failed, comments: [new(10, 10, "Ali")]);
        var after = Item("APPROVED", "CONFLICTED", BuildState.Passed, [new(12, 12, "Veli"), new(11, 11, "Ali"), new(10, 10, "Ali")]);
        var old = Snapshot.Create([], [before], null, _ => true);
        var current = Snapshot.Create([], [after], old, _ => true);
        var body = Assert.Single(ChangeDetector.Changes(old, current, [], [after])).Body;

        Assert.Equal("✅ Sam Reviewer onayladı\n⚠️ Birleştirme çakışmaları\n✅ Derleme düzeldi\n💬 2 yeni yorum: Ali, Veli", body);
    }

    [Fact]
    public void Errors_are_written_in_the_chosen_language()
    {
        Localizer.Apply(LanguagePreference.Turkish);
        Assert.Equal("Bitbucket HTTP 502 döndürdü.", new ApiException(ApiErrorKind.Http, 502).Message);
        Assert.Equal("Sunucu adresi https:// ile başlamalıdır.",
            Assert.Throws<ServerAddress.InvalidException>(() => ServerAddress.Parse("http://x.example.com")).Message);
    }

    [Fact]
    public void English_plurals()
    {
        Assert.Equal("💬 1 new comment from Ali", L10n.NotifyComments(1, "Ali"));
        Assert.Equal("💬 2 new comments from Ali, Veli", L10n.NotifyComments(2, "Ali, Veli"));
    }
}
