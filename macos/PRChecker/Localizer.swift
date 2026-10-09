import Foundation
import Observation

/// Languages the app's strings exist in (see shared/localization/strings.json).
nonisolated enum AppLanguage: Sendable {
    case english, turkish
}

/// The user's choice in Settings; `.system` follows the macOS preferred language.
nonisolated enum LanguagePreference: String, CaseIterable, Sendable {
    case system, english, turkish
}

/// The language every `L10n` string is returned in. Views that read `L10n` redraw when it
/// changes, so switching languages needs no restart. Read from any thread (error messages are
/// built off the main actor); it's only written on the main actor, from Settings.
@Observable
nonisolated final class Localizer: @unchecked Sendable {
    static let shared = Localizer()

    /// Lets a test use a language for its own task only, without touching the app-wide one
    /// that tests running in parallel see.
    @TaskLocal static var override: AppLanguage?

    /// The language `L10n` uses right now.
    static var current: AppLanguage { override ?? shared.language }

    private(set) var language: AppLanguage = .english

    /// For formatting dates and numbers the way the chosen language expects.
    var locale: Locale { Locale(identifier: language == .turkish ? "tr_TR" : "en_US") }

    /// The first macOS preferred language, e.g. "tr-TR". Tests replace it.
    @ObservationIgnored var systemLanguage: () -> String = { Locale.preferredLanguages.first ?? "en" }

    /// Turkish when chosen, or when following a Turkish system; English otherwise.
    func resolve(_ preference: LanguagePreference) -> AppLanguage {
        switch preference {
        case .english: .english
        case .turkish: .turkish
        case .system: systemLanguage().lowercased().hasPrefix("tr") ? .turkish : .english
        }
    }

    func apply(_ preference: LanguagePreference) {
        let resolved = resolve(preference)
        if resolved != language { language = resolved }
    }
}
