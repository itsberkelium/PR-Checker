import Foundation
import Synchronization

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited
    case http(Int)
    case badResponse
    case paginationStalled
    case tooManyResults(limit: Int)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .unauthorized: "The access token was rejected. Check it in Settings."
        case .rateLimited: "Bitbucket is limiting requests. PR Checker will try again later."
        case .http(let code): "Bitbucket returned HTTP \(code)."
        case .badResponse: "Unexpected response from Bitbucket."
        case .paginationStalled: "Bitbucket returned an inconsistent page sequence."
        case .tooManyResults(let limit): "More than \(limit) open pull requests; narrow it down with filters."
        case .responseTooLarge: "Bitbucket sent an unexpectedly large response."
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

    static let pageSize = 100
    static let maxPages = 20
    static let maxResponseBytes = 8 * 1024 * 1024

    /// No disk cache or cookies, so API responses aren't persisted anywhere.
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    let server: ServerAddress
    let token: String
    var session: URLSession = BitbucketClient.defaultSession

    func dashboard(role: Role) async throws -> Dashboard {
        var result = Dashboard(pullRequests: [])
        var start = 0
        for _ in 0..<Self.maxPages {
            try Task.checkCancellation()
            let (data, response) = try await get("rest/api/1.0/dashboard/pull-requests", query: [
                URLQueryItem(name: "role", value: role.rawValue),
                URLQueryItem(name: "state", value: "OPEN"),
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
                URLQueryItem(name: "start", value: String(start)),
            ])
            result.username = result.username ?? response.value(forHTTPHeaderField: "X-AUSERNAME")
            let page = try JSONDecoder().decode(Page<PullRequest>.self, from: data)
            result.pullRequests += page.values
            guard !page.isLastPage, let next = page.nextPageStart else { return result }
            guard next > start else { throw APIError.paginationStalled }
            start = next
        }
        throw APIError.tooManyResults(limit: Self.maxPages * Self.pageSize)
    }

    /// The signed-in user name; one small request, used to validate a connection.
    func currentUser() async throws -> String {
        let (_, response) = try await get("rest/api/1.0/dashboard/pull-requests", query: [
            URLQueryItem(name: "limit", value: "1"),
        ])
        if let name = response.value(forHTTPHeaderField: "X-AUSERNAME"), !name.isEmpty { return name }
        return try await whoami()
    }

    func whoami() async throws -> String {
        let (data, _) = try await get("plugins/servlet/applinks/whoami")
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count < 256, !name.contains("<") else { throw APIError.badResponse }
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
        let key = projectKey.addingPercentEncoding(withAllowedCharacters: .urlPathComponentAllowed) ?? ""
        let slug = repoSlug.addingPercentEncoding(withAllowedCharacters: .urlPathComponentAllowed) ?? ""
        return "rest/api/1.0/projects/\(key)/repos/\(slug)/pull-requests/\(number)"
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.badResponse
        }
        components.percentEncodedPath = server.path + "/" + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url, server.owns(url) else { throw APIError.badResponse }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await CappedRequest(server: server, maxBytes: Self.maxResponseBytes)
            .run(request, in: session)
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.http(http.statusCode)
        }
    }
}

/// Runs one request and collects its body in chunks, cancelling as soon as it
/// exceeds `maxBytes`. Redirects are followed only within the configured server,
/// so the Authorization header can't be carried to another host; a refused
/// redirect comes back as its 3xx response.
nonisolated private final class CappedRequest: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var data = Data()
        var response: HTTPURLResponse?
        var tooLarge = false
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    }

    private let server: ServerAddress
    private let maxBytes: Int
    private let state = Mutex(State())

    init(server: ServerAddress, maxBytes: Int) {
        self.server = server
        self.maxBytes = maxBytes
    }

    func run(_ request: URLRequest, in session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let task = session.dataTask(with: request)
        task.delegate = self
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.withLock { $0.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let tooLarge = response.expectedContentLength > maxBytes
        state.withLock {
            $0.response = response as? HTTPURLResponse
            $0.tooLarge = tooLarge
        }
        completionHandler(tooLarge ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overLimit = state.withLock { state -> Bool in
            state.data.append(data)
            if state.data.count > maxBytes { state.tooLarge = true }
            return state.tooLarge
        }
        if overLimit { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, result) = state.withLock { state -> (CheckedContinuation<(Data, HTTPURLResponse), Error>?, Result<(Data, HTTPURLResponse), Error>) in
            let continuation = state.continuation
            state.continuation = nil
            if state.tooLarge { return (continuation, .failure(APIError.responseTooLarge)) }
            if let error { return (continuation, .failure(error)) }
            guard let response = state.response else { return (continuation, .failure(APIError.badResponse)) }
            return (continuation, .success((state.data, response)))
        }
        continuation?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(server.owns(request.url) ? request : nil)
    }
}

extension CharacterSet {
    /// Path-safe characters minus "/", for encoding a single path component.
    nonisolated static let urlPathComponentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
}
