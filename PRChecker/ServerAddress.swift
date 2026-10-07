import Foundation

/// A validated Bitbucket server base URL, e.g. `https://bitbucket.example.com/context`.
/// Tokens and locally stored PR data are scoped to `id`, links are only opened
/// and redirects only followed when `owns(_:)` accepts them.
nonisolated struct ServerAddress: Equatable, Hashable, Sendable {
    enum Problem: LocalizedError {
        case invalid, notHTTPS, hasCredentials, hasQueryOrFragment

        var errorDescription: String? {
            switch self {
            case .invalid: "Enter a server URL like https://bitbucket.example.com."
            case .notHTTPS: "The server URL must start with https://."
            case .hasCredentials: "Remove the user name or password from the server URL."
            case .hasQueryOrFragment: "Remove the ?query or #fragment from the server URL."
            }
        }
    }

    /// Normalized: lowercase scheme and host, default port dropped, no trailing slash.
    let baseURL: URL
    let host: String
    let port: Int
    /// Context path without trailing slash, "" at the root.
    let path: String

    /// Stable identifier for scoping Keychain items and stored data.
    var id: String { baseURL.absoluteString }

    init(parsing raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed), let scheme = parts.scheme?.lowercased() else {
            throw Problem.invalid
        }
        guard scheme == "https" else { throw Problem.notHTTPS }
        guard let host = parts.host?.lowercased(), !host.isEmpty else { throw Problem.invalid }
        guard parts.user == nil, parts.password == nil else { throw Problem.hasCredentials }
        guard parts.query == nil, parts.fragment == nil else { throw Problem.hasQueryOrFragment }

        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }

        parts.scheme = "https"
        parts.host = host
        if parts.port == 443 { parts.port = nil }
        parts.path = path
        guard let url = parts.url else { throw Problem.invalid }

        baseURL = url
        self.host = host
        port = parts.port ?? 443
        self.path = path
    }

    /// Whether `url` is an https URL on this server, inside its context path.
    func owns(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.host()?.lowercased() == host,
              (url.port ?? 443) == port,
              url.user == nil, url.password == nil else { return false }
        let candidate = url.path(percentEncoded: true)
        return path.isEmpty || candidate == path || candidate.hasPrefix(path + "/")
    }

    /// Web page of a pull request, built from trusted configuration rather than
    /// links in API responses. Each identifier is encoded as a single path component.
    func pullRequestURL(projectKey: String, repoSlug: String, number: Int) -> URL {
        baseURL
            .appending(component: "projects").appending(component: projectKey)
            .appending(component: "repos").appending(component: repoSlug)
            .appending(component: "pull-requests").appending(component: String(number))
    }
}
