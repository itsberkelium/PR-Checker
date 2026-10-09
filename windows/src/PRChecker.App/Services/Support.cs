using System.Diagnostics;
using System.Runtime.InteropServices;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>Links for Report a Problem and the legal documents.</summary>
internal static class Support
{
    private const string Repository = "https://github.com/itsberkelium/PR-Checker";
    public const string PrivacyPolicy = Repository + "/blob/main/PRIVACY.md";
    public const string TermsOfUse = Repository + "/blob/main/TERMS.md";

    /// <summary>
    /// A new issue with the bug report form, pre-filled with the app version, Windows version and
    /// language. Nothing is sent: the user reviews and submits it on GitHub.
    /// </summary>
    public static string ReportProblemUrl(LanguagePreference preference)
    {
        // English, since issues are written in English: "Turkish (system)", "English".
        var language = Localizer.Language == AppLanguage.Turkish ? "Turkish" : "English";
        if (preference == LanguagePreference.System) language += " (system)";
        var fields = new Dictionary<string, string>
        {
            ["template"] = "bug_report.yml",
            ["platform"] = "Windows",
            ["version"] = Platform.Version,
            ["os"] = $"{RuntimeInformation.OSDescription} ({RuntimeInformation.OSArchitecture})",
            ["language"] = language,
        };
        return Repository + "/issues/new?" + string.Join("&", fields.Select(f => $"{f.Key}={Uri.EscapeDataString(f.Value)}"));
    }

    public static void Open(string target) => Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });

    /// <summary>The license notices shipped next to the app, in the default text viewer.</summary>
    public static void OpenThirdPartyLicenses() => Open(Path.Combine(AppContext.BaseDirectory, "THIRD-PARTY-NOTICES.txt"));

    public static void OpenLog()
    {
        if (File.Exists(Log.FilePath)) Open(Log.FilePath);
    }
}
