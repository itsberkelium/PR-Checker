import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let refreshOptions = [1, 2, 5, 10, 15]

    enum ConnectionError: LocalizedError {
        case tokenRequired

        var errorDescription: String? {
            "Enter the access token for this server."
        }
    }

    private enum Key {
        static let serverURL = "serverURL"
        static let refreshMinutes = "refreshMinutes"
        static let hideDrafts = "hideDrafts"
        static let repoFilter = "repoFilter"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationDetails = "notificationDetails"
        static let automationEnabled = "automationEnabled"
        static let automationCommand = "automationCommand"
    }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let tokens: TokenStore
    /// Read from the Keychain once per server; every read can trigger an access prompt.
    @ObservationIgnored private var cachedToken: (serverID: String, token: String?)?
    @ObservationIgnored private var filterPatterns: [String] = []
    /// Replaced in tests with a session that talks to a stub server.
    @ObservationIgnored var session: URLSession = BitbucketClient.defaultSession

    /// The connected server; changed only through `applyConnection` and `signOut`.
    private(set) var server: ServerAddress?
    var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: Key.refreshMinutes) } }
    var hideDrafts: Bool { didSet { defaults.set(hideDrafts, forKey: Key.hideDrafts) } }
    /// Comma-separated project keys or "PROJECT/repo-slug" entries. Empty shows everything.
    var repoFilter: String {
        didSet {
            defaults.set(repoFilter, forKey: Key.repoFilter)
            filterPatterns = Self.parsePatterns(repoFilter)
        }
    }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    /// Off: notifications say only that something changed, without titles or names.
    var notificationDetails: Bool { didSet { defaults.set(notificationDetails, forKey: Key.notificationDetails) } }
    /// Runs `automationCommand` when a PR enters the review list or gets new commits.
    var automationEnabled: Bool { didSet { defaults.set(automationEnabled, forKey: Key.automationEnabled) } }
    var automationCommand: String { didSet { defaults.set(automationCommand, forKey: Key.automationCommand) } }

    init(defaults: UserDefaults = .standard, tokens: TokenStore = Keychain()) {
        self.defaults = defaults
        self.tokens = tokens
        if defaults.string(forKey: Key.serverURL) == nil && !Self.bundledServerURL.isEmpty {
            // Save a build-time default so later builds without one keep working.
            defaults.set(Self.bundledServerURL, forKey: Key.serverURL)
        }
        server = defaults.string(forKey: Key.serverURL).flatMap { try? ServerAddress(parsing: $0) }
        refreshMinutes = defaults.object(forKey: Key.refreshMinutes) as? Int ?? 5
        hideDrafts = defaults.object(forKey: Key.hideDrafts) as? Bool ?? true
        repoFilter = defaults.string(forKey: Key.repoFilter) ?? ""
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        notificationDetails = defaults.object(forKey: Key.notificationDetails) as? Bool ?? true
        automationEnabled = defaults.object(forKey: Key.automationEnabled) as? Bool ?? false
        automationCommand = defaults.string(forKey: Key.automationCommand) ?? ""
        filterPatterns = Self.parsePatterns(repoFilter)
    }

    /// Optional default baked in at build time from Config/Local.xcconfig (DEFAULT_SERVER_URL).
    private static var bundledServerURL: String {
        Bundle.main.object(forInfoDictionaryKey: "PRCheckerDefaultServerURL") as? String ?? ""
    }

    /// The server URL as last saved, for pre-filling the settings form.
    var savedServerURL: String {
        defaults.string(forKey: Key.serverURL) ?? ""
    }

    func hasToken(for server: ServerAddress) -> Bool {
        !(token(for: server) ?? "").isEmpty
    }

    func makeClient() -> BitbucketClient? {
        guard let server, let token = token(for: server), !token.isEmpty else { return nil }
        return BitbucketClient(server: server, token: token, session: session)
    }

    /// Client for a connection that hasn't been applied yet. A blank token reuses
    /// the saved one only for the same server, so a token never goes to a new host.
    func draftClient(serverURL: String, token draftToken: String) throws -> BitbucketClient {
        let candidate = try ServerAddress(parsing: serverURL)
        let trimmed = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = trimmed.isEmpty ? (self.token(for: candidate) ?? "") : trimmed
        guard !token.isEmpty else { throw ConnectionError.tokenRequired }
        return BitbucketClient(server: candidate, token: token, session: session)
    }

    /// Saves a validated connection. The token is written first; if that fails
    /// nothing changes. A previous server's token is removed when switching.
    func applyConnection(_ client: BitbucketClient) throws {
        try tokens.save(client.token, account: Keychain.account(for: client.server))
        if let old = server, old != client.server {
            try? tokens.delete(account: Keychain.account(for: old))
        }
        cachedToken = (client.server.id, client.token)
        defaults.set(client.server.id, forKey: Key.serverURL)
        server = client.server
    }

    /// Removes the token for the current server. The server URL stays for convenience.
    func signOut() throws {
        if let server {
            try tokens.delete(account: Keychain.account(for: server))
            cachedToken = (server.id, nil)
        }
    }

    private func token(for server: ServerAddress) -> String? {
        if let cachedToken, cachedToken.serverID == server.id { return cachedToken.token }
        var token = tokens.read(account: Keychain.account(for: server))
        if token == nil, server == self.server, let legacy = tokens.read(account: Keychain.legacyAccount) {
            // One-time move of the pre-0.2.6 token to the per-server item.
            if (try? tokens.save(legacy, account: Keychain.account(for: server))) != nil {
                try? tokens.delete(account: Keychain.legacyAccount)
            }
            token = legacy
        }
        cachedToken = (server.id, token)
        return token
    }

    func includes(_ item: PRItem) -> Bool {
        if hideDrafts && item.isDraft { return false }
        guard !filterPatterns.isEmpty else { return true }
        let project = item.projectKey.lowercased()
        let repo = "\(project)/\(item.repoSlug.lowercased())"
        return filterPatterns.contains { $0 == project || $0 == repo }
    }

    private static func parsePatterns(_ filter: String) -> [String] {
        filter.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}
