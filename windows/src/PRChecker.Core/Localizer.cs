using System.Globalization;
using System.Text.Json.Serialization;

namespace PRChecker.Core;

/// <summary>Languages the app's strings exist in (see shared/localization/strings.json).</summary>
public enum AppLanguage { English, Turkish }

/// <summary>The user's choice in Settings; <see cref="System"/> follows the Windows display language.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<LanguagePreference>))]
public enum LanguagePreference { System, English, Turkish }

/// <summary>
/// The language every <see cref="L10n"/> string is returned in. Changing it raises
/// <see cref="Changed"/> so the UI can redraw without a restart.
/// </summary>
public static class Localizer
{
    private static readonly CultureInfo TurkishCulture = CultureInfo.GetCultureInfo("tr-TR");
    private static readonly CultureInfo EnglishCulture = CultureInfo.GetCultureInfo("en-US");

    /// <summary>The OS display language, captured at startup. Tests replace it.</summary>
    public static CultureInfo SystemCulture { get; set; } = CultureInfo.CurrentUICulture;

    public static AppLanguage Language { get; private set; } = AppLanguage.English;

    /// <summary>For formatting numbers and dates the way the chosen language expects.</summary>
    public static CultureInfo Culture => Language == AppLanguage.Turkish ? TurkishCulture : EnglishCulture;

    public static event Action? Changed;

    /// <summary>Turkish when chosen, or when following a Turkish OS; English otherwise.</summary>
    public static AppLanguage Resolve(LanguagePreference preference) => preference switch
    {
        LanguagePreference.English => AppLanguage.English,
        LanguagePreference.Turkish => AppLanguage.Turkish,
        _ => SystemCulture.TwoLetterISOLanguageName == "tr" ? AppLanguage.Turkish : AppLanguage.English,
    };

    public static void Apply(LanguagePreference preference)
    {
        var language = Resolve(preference);
        if (language == Language) return;
        Language = language;
        Changed?.Invoke();
    }
}
