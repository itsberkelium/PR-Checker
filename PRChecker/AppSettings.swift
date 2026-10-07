import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let refreshOptions = [1, 2, 5, 10, 15]

    private enum Key {
        static let serverURL = "serverURL"
        static let refreshMinutes = "refreshMinutes"
        static let hideDrafts = "hideDrafts"
        static let repoFilter = "repoFilter"
        static let notificationsEnabled = "notificationsEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Read from the Keychain once; every read can trigger an access prompt.
    @ObservationIgnored private lazy var cachedToken: String? = Keychain.readToken()

    var token: String { cachedToken ?? "" }

    func saveToken(_ token: String) {
        Keychain.saveToken(token)
        cachedToken = token
    }

    var serverURL: String { didSet { defaults.set(serverURL, forKey: Key.serverURL) } }
    var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: Key.refreshMinutes) } }
    var hideDrafts: Bool { didSet { defaults.set(hideDrafts, forKey: Key.hideDrafts) } }
    /// Comma-separated project keys or "PROJECT/repo-slug" entries. Empty shows everything.
    var repoFilter: String { didSet { defaults.set(repoFilter, forKey: Key.repoFilter) } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverURL = defaults.string(forKey: Key.serverURL) ?? Self.bundledServerURL
        refreshMinutes = defaults.object(forKey: Key.refreshMinutes) as? Int ?? 5
        hideDrafts = defaults.object(forKey: Key.hideDrafts) as? Bool ?? true
        repoFilter = defaults.string(forKey: Key.repoFilter) ?? ""
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
    }

    /// Optional default baked in at build time from Config/Local.xcconfig (DEFAULT_SERVER_URL).
    private static var bundledServerURL: String {
        Bundle.main.object(forInfoDictionaryKey: "PRCheckerDefaultServerURL") as? String ?? ""
    }

    func makeClient() -> BitbucketClient? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https", url.host() != nil,
              !token.isEmpty else { return nil }
        return BitbucketClient(baseURL: url, token: token)
    }

    func includes(_ item: PRItem) -> Bool {
        if hideDrafts && item.isDraft { return false }
        let patterns = repoFilter
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return true }
        let project = item.projectKey.lowercased()
        let repo = "\(project)/\(item.repoSlug.lowercased())"
        return patterns.contains { $0 == project || $0 == repo }
    }
}
