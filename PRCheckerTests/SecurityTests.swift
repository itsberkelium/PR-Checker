import Foundation
import Synchronization
import Testing
@testable import PR_Checker

// MARK: - Server address and links

@MainActor
struct ServerAddressTests {
    @Test func normalizesValidURLs() throws {
        let server = try ServerAddress(parsing: "  HTTPS://Bitbucket.Example.com:443/context/ ")
        #expect(server.id == "https://bitbucket.example.com/context")
        #expect(server.port == 443)
    }

    @Test func rejectsUnsafeURLs() {
        #expect(throws: ServerAddress.Problem.notHTTPS) { try ServerAddress(parsing: "http://bitbucket.example.com") }
        #expect(throws: ServerAddress.Problem.hasCredentials) { try ServerAddress(parsing: "https://me:pw@bitbucket.example.com") }
        #expect(throws: ServerAddress.Problem.hasQueryOrFragment) { try ServerAddress(parsing: "https://bitbucket.example.com/?x=1") }
        #expect(throws: ServerAddress.Problem.hasQueryOrFragment) { try ServerAddress(parsing: "https://bitbucket.example.com/#top") }
        #expect(throws: (any Error).self) { try ServerAddress(parsing: "not a url") }
    }

    @Test func ownsOnlyItsOwnPages() throws {
        let server = try ServerAddress(parsing: "https://bitbucket.example.com/bb")
        #expect(server.owns(URL(string: "https://BITBUCKET.example.com/bb/projects/P")))
        #expect(!server.owns(URL(string: "https://bitbucket.example.com/other")))
        #expect(!server.owns(URL(string: "https://bitbucket.example.com/bbx")))
        #expect(!server.owns(URL(string: "https://evil.example.com/bb/projects/P")))
        #expect(!server.owns(URL(string: "https://bitbucket.example.com:8443/bb")))
        #expect(!server.owns(URL(string: "http://bitbucket.example.com/bb")))
        #expect(!server.owns(URL(string: "file:///etc/passwd")))
        #expect(!server.owns(URL(string: "otherapp://bitbucket.example.com/bb")))
    }

    @Test func buildsPRLinksFromConfigurationNotTheAPI() throws {
        // The fixture's API link is file:///etc/passwd.
        let item = PRItem(try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "a"), server: testServer)
        #expect(item.url.absoluteString == "https://bitbucket.example.com/projects/PROJ/repos/web-app/pull-requests/2583")

        let tricky = testServer.pullRequestURL(projectKey: "../..", repoSlug: "a/b?c#d", number: 1)
        #expect(testServer.owns(tricky))
        #expect(tricky.query == nil && tricky.fragment == nil)
    }
}

// MARK: - Token handling

/// In-memory TokenStore that can be told to fail writes.
final class MemoryTokenStore: TokenStore {
    var items: [String: String] = [:]
    var failWrites = false

    func read(account: String) -> String? { items[account] }

    func save(_ token: String, account: String) throws {
        if failWrites { throw KeychainError(status: errSecInteractionNotAllowed) }
        items[account] = token
    }

    func delete(account: String) throws {
        if failWrites { throw KeychainError(status: errSecInteractionNotAllowed) }
        items[account] = nil
    }
}

@MainActor
struct TokenHandlingTests {
    let serverA = try! ServerAddress(parsing: "https://a.example.com")
    let serverB = try! ServerAddress(parsing: "https://b.example.com")

    private func connected(to server: ServerAddress, token: String) throws -> (AppSettings, MemoryTokenStore) {
        let store = MemoryTokenStore()
        let settings = AppSettings(defaults: freshDefaults(), tokens: store)
        try settings.applyConnection(BitbucketClient(server: server, token: token))
        return (settings, store)
    }

    @Test func savedTokenIsNeverReusedForAnotherServer() throws {
        let (settings, _) = try connected(to: serverA, token: "token-a")
        #expect(throws: AppSettings.ConnectionError.tokenRequired) {
            try settings.draftClient(serverURL: "https://b.example.com", token: "")
        }
        #expect(try settings.draftClient(serverURL: "https://a.example.com/", token: "").token == "token-a")
        #expect(try settings.draftClient(serverURL: "https://b.example.com", token: "token-b").token == "token-b")
    }

    @Test func tokensAreScopedPerServerAndOldOnesRemoved() throws {
        let (settings, store) = try connected(to: serverA, token: "token-a")
        try settings.applyConnection(BitbucketClient(server: serverB, token: "token-b"))
        #expect(store.items == [Keychain.account(for: serverB): "token-b"])
        #expect(settings.makeClient()?.server == serverB)
    }

    @Test func failedKeychainWriteChangesNothing() throws {
        let (settings, store) = try connected(to: serverA, token: "token-a")
        store.failWrites = true
        #expect(throws: KeychainError.self) {
            try settings.applyConnection(BitbucketClient(server: serverB, token: "token-b"))
        }
        #expect(settings.server == serverA)
        #expect(settings.makeClient()?.token == "token-a")
        #expect(store.items[Keychain.account(for: serverA)] == "token-a")
    }

    @Test func migratesTheLegacyToken() throws {
        let defaults = freshDefaults()
        defaults.set("https://a.example.com", forKey: "serverURL")
        let store = MemoryTokenStore()
        store.items[Keychain.legacyAccount] = "old-token"
        let settings = AppSettings(defaults: defaults, tokens: store)

        #expect(settings.makeClient()?.token == "old-token")
        #expect(store.items == [Keychain.account(for: serverA): "old-token"])
    }
}

// MARK: - Network limits and redirects

@MainActor
@Suite(.serialized)
struct NetworkTests {
    let server = try! ServerAddress(parsing: "https://a.example.com")

    private func client() -> BitbucketClient {
        BitbucketClient(server: server, token: "token-a", session: StubServer.session)
    }

    @Test func stalledPaginationStops() async throws {
        StubServer.reset { _ in .json(#"{"values":[],"isLastPage":false,"nextPageStart":0}"#) }
        await #expect(throws: APIError.paginationStalled) { try await client().dashboard(role: .reviewer) }
        #expect(StubServer.requests.count == 1)
    }

    @Test func endlessPaginationIsCapped() async throws {
        StubServer.reset { request in
            let start = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "start" }!.value!)!
            return .json(#"{"values":[],"isLastPage":false,"nextPageStart":\#(start + 100)}"#)
        }
        await #expect(throws: APIError.tooManyResults(limit: 2000)) { try await client().dashboard(role: .reviewer) }
        #expect(StubServer.requests.count == BitbucketClient.maxPages)
    }

    @Test func oversizedResponsesAreRejected() async throws {
        let oversized = String(repeating: " ", count: BitbucketClient.maxResponseBytes + 1)
        StubServer.reset { _ in .json(oversized) }
        await #expect(throws: APIError.responseTooLarge) { try await client().buildState(commit: "abc") }
    }

    @Test func redirectsToAnotherHostAreNotFollowed() async throws {
        StubServer.reset { request in
            request.url?.host() == "a.example.com"
                ? .redirect(to: "https://evil.example.com/steal")
                : .json(#"{"successful":1}"#)
        }
        await #expect(throws: APIError.http(302)) { try await client().buildState(commit: "abc") }
        #expect(StubServer.requests.allSatisfy { $0.host == "a.example.com" })
    }

    @Test func redirectsWithinTheServerAreFollowed() async throws {
        StubServer.reset { request in
            request.url?.path().hasPrefix("/moved") == true
                ? .json(#"{"failed":1}"#)
                : .redirect(to: "https://a.example.com/moved")
        }
        #expect(try await client().buildState(commit: "abc") == .failed)
    }

    @Test func rateLimitingIsReported() async throws {
        StubServer.reset { _ in .status(429) }
        await #expect(throws: APIError.rateLimited) { try await client().buildState(commit: "abc") }
    }
}

// MARK: - Connection switching

@MainActor
@Suite(.serialized)
struct ConnectionTests {
    @Test func newServerWithoutTokenSendsNothing() async throws {
        StubServer.reset { _ in .json("{}") }
        let settings = AppSettings(defaults: freshDefaults(), tokens: MemoryTokenStore())
        settings.session = StubServer.session
        try settings.applyConnection(BitbucketClient(server: try ServerAddress(parsing: "https://a.example.com"), token: "token-a"))
        let store = PRStore(settings: settings)

        await #expect(throws: AppSettings.ConnectionError.tokenRequired) {
            try await store.connect(serverURL: "https://b.example.com", token: "")
        }
        #expect(StubServer.requests.isEmpty)
        #expect(settings.server?.host == "a.example.com")
    }

    @Test func staleRefreshFromOldServerIsDiscarded() async throws {
        let slowPR = Self.dashboardJSON(prID: 7)
        StubServer.reset { request in
            if request.url?.host() == "a.example.com" {
                if request.url?.path().contains("dashboard") == true {
                    Thread.sleep(forTimeInterval: 0.6) // still in flight when we switch
                    return .json(slowPR, user: "sam.reviewer")
                }
                return .json(#"{"values":[],"isLastPage":true}"#)
            }
            return .json(#"{"values":[],"isLastPage":true}"#, user: "sam.reviewer")
        }
        let tokens = MemoryTokenStore()
        let settings = AppSettings(defaults: freshDefaults(), tokens: tokens)
        settings.notificationsEnabled = false
        settings.session = StubServer.session
        try settings.applyConnection(BitbucketClient(server: try ServerAddress(parsing: "https://a.example.com"), token: "token-a"))
        let store = PRStore(settings: settings)

        let oldRefresh = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(200))
        let name = try await store.connect(serverURL: "https://b.example.com", token: "token-b")
        await oldRefresh.value
        try await Task.sleep(for: .milliseconds(800))

        #expect(name == "sam.reviewer")
        #expect(store.reviewItems.isEmpty && store.mineItems.isEmpty)
        #expect(StubServer.requests.filter { $0.host == "b.example.com" }.allSatisfy { $0.token == "token-b" })
        #expect(StubServer.requests.filter { $0.host == "a.example.com" }.allSatisfy { $0.token == "token-a" })
        #expect(!settings.defaults.dictionaryRepresentation().keys.contains { $0.contains("a.example.com") })
    }

    private static func dashboardJSON(prID: Int) -> String {
        let pr = String(decoding: try! JSONSerialization.data(withJSONObject: [
            "id": prID, "title": "T", "updatedDate": 0,
            "fromRef": ["displayId": "f", "latestCommit": "c", "repository": ["slug": "r", "name": "R", "project": ["key": "P"]]],
            "toRef": ["displayId": "t", "latestCommit": "d", "repository": ["slug": "r", "name": "R", "project": ["key": "P"]]],
            "author": ["user": ["name": "x", "slug": "x"], "status": "UNAPPROVED"],
            "reviewers": [["user": ["name": "sam.reviewer", "slug": "sam.reviewer"], "status": "UNAPPROVED"]],
        ]), as: UTF8.self)
        return #"{"values":[\#(pr)],"isLastPage":true}"#
    }
}

// MARK: - Stub server

func freshDefaults() -> UserDefaults {
    let suite = "dev.berke.PRCheckerTests"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// URLProtocol that answers every request and records host, path and token.
nonisolated final class StubServer: URLProtocol {
    enum Reply: Sendable {
        case json(String, user: String? = nil)
        case status(Int)
        case redirect(to: String)
    }

    struct Request: Sendable {
        let host: String?
        let path: String
        let token: String?
    }

    private struct State {
        var handler: @Sendable (URLRequest) -> Reply = { _ in .status(500) }
        var requests: [Request] = []
    }

    private static let state = Mutex(State())

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }()

    static var requests: [Request] { state.withLock { $0.requests } }

    static func reset(_ handler: @escaping @Sendable (URLRequest) -> Reply) {
        state.withLock { $0 = State(handler: handler, requests: []) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let request = self.request
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        let handler = Self.state.withLock { state in
            state.requests.append(Request(host: request.url?.host(), path: request.url?.path() ?? "", token: token))
            return state.handler
        }
        let url = request.url!
        switch handler(request) {
        case .json(let body, let user):
            var headers = ["Content-Type": "application/json"]
            if let user { headers["X-AUSERNAME"] = user }
            respond(url: url, status: 200, headers: headers, body: Data(body.utf8))
        case .status(let code):
            respond(url: url, status: code, headers: [:], body: Data())
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target])!
            var next = request
            next.url = URL(string: target)
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            // Reached only when the redirect is refused: deliver the 302 itself.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func respond(url: URL, status: Int, headers: [String: String], body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
