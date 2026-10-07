import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: "The access token was rejected. Check it in Settings."
        case .http(let code): "Bitbucket returned HTTP \(code)."
        case .badResponse: "Unexpected response from Bitbucket."
        }
    }
}

/// Minimal Bitbucket Server / Data Center REST client using an HTTP access token.
struct BitbucketClient {
    enum Role: String {
        case reviewer = "REVIEWER"
        case author = "AUTHOR"
    }

    struct Dashboard {
        var pullRequests: [PullRequest]
        /// Taken from the X-AUSERNAME response header when the server sends it.
        var username: String?
    }

    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    func dashboard(role: Role) async throws -> Dashboard {
        var result = Dashboard(pullRequests: [])
        var start = 0
        while true {
            let (data, response) = try await get("rest/api/1.0/dashboard/pull-requests", query: [
                URLQueryItem(name: "role", value: role.rawValue),
                URLQueryItem(name: "state", value: "OPEN"),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "start", value: String(start)),
            ])
            result.username = result.username ?? response.value(forHTTPHeaderField: "X-AUSERNAME")
            let page = try JSONDecoder().decode(Page<PullRequest>.self, from: data)
            result.pullRequests += page.values
            guard !page.isLastPage, let next = page.nextPageStart else { break }
            start = next
        }
        return result
    }

    func whoami() async throws -> String {
        let (data, _) = try await get("plugins/servlet/applinks/whoami")
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("<") else { throw APIError.badResponse }
        return name
    }

    func buildState(commit: String) async throws -> BuildState {
        let (data, _) = try await get("rest/build-status/1.0/commits/stats/\(commit)")
        let stats = try JSONDecoder().decode(BuildStats.self, from: data)
        if (stats.failed ?? 0) > 0 { return .failed }
        if (stats.inProgress ?? 0) > 0 { return .running }
        if (stats.successful ?? 0) > 0 { return .passed }
        return .none
    }

    /// Most recent comments and replies on a PR, excluding the given user's own.
    func commentsByOthers(on item: PRItem, excluding username: String) async throws -> [PRItem.Comment] {
        let path = pullRequestPath(projectKey: item.projectKey, repoSlug: item.repoSlug, number: item.number)
        let (data, _) = try await get(path + "/activities", query: [
            URLQueryItem(name: "limit", value: "50"),
        ])
        return try JSONDecoder().decode(Page<Activity>.self, from: data).values
            .filter { $0.action == "COMMENTED" && ["ADDED", "REPLIED"].contains($0.commentAction ?? "") }
            .filter { !$0.user.isSameUser(as: username) }
            .map { PRItem.Comment(id: $0.id, created: $0.createdDate, author: $0.user.displayName ?? $0.user.name) }
    }

    /// "OPEN", "MERGED" or "DECLINED".
    func state(projectKey: String, repoSlug: String, number: Int) async throws -> String {
        let (data, _) = try await get(pullRequestPath(projectKey: projectKey, repoSlug: repoSlug, number: number))
        return try JSONDecoder().decode(PullRequestState.self, from: data).state
    }

    private func pullRequestPath(projectKey: String, repoSlug: String, number: Int) -> String {
        "rest/api/1.0/projects/\(projectKey)/repos/\(repoSlug)/pull-requests/\(number)"
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw APIError.unauthorized
        default: throw APIError.http(http.statusCode)
        }
    }
}
