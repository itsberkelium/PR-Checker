import AppKit
import Foundation

/// Links for Report a Problem and the legal documents.
enum Support {
    static let repository = URL(string: "https://github.com/itsberkelium/PR-Checker")!
    static let privacyPolicy = repository.appending(path: "blob/main/PRIVACY.md")
    static let termsOfUse = repository.appending(path: "blob/main/TERMS.md")

    /// A new issue with the bug report form, pre-filled with the app version, macOS version and
    /// language. Nothing is sent: the user reviews and submits it on GitHub.
    static func reportProblemURL(
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
        system: String = "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
        language: String = languageDescription()
    ) -> URL {
        var components = URLComponents(url: repository.appending(path: "issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "platform", value: "macOS"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "os", value: system),
            URLQueryItem(name: "language", value: language),
        ]
        return components.url!
    }

    /// English, since issues are written in English: "Turkish (system)", "English".
    static func languageDescription(
        language: AppLanguage = Localizer.current, preference: LanguagePreference = AppSettings.shared.language
    ) -> String {
        let name = language == .turkish ? "Turkish" : "English"
        return preference == .system ? "\(name) (system)" : name
    }

    /// The license notices bundled with the app, opened in the default text viewer.
    static func openThirdPartyLicenses() {
        if let notices = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt") {
            NSWorkspace.shared.open(notices)
        }
    }
}
