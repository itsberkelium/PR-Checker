import Foundation

/// What the app needs from a code host. Each provider turns its own API payloads into
/// `PRItem`s, so the store, notifications and views don't depend on any one host.
/// Bitbucket Server / Data Center (`BitbucketClient`) is the only provider so far.
protocol PRProvider: Sendable {
    var server: ServerAddress { get }
    var token: String { get }

    /// The signed-in user name; one small request, used to validate a connection.
    func currentUser() async throws -> String
    /// Open PRs waiting for my review and my own open PRs, with the signed-in user name.
    /// Review PRs I've already handled are left out (see "Review list" in docs/behavior.md).
    func openPullRequests() async throws -> OpenPullRequests
    /// My recently merged PRs, most recently merged first, each with `merged` set.
    func recentlyMerged() async throws -> [PRItem]
    /// Recent comments and replies on a PR, excluding the given user's own.
    func commentsByOthers(on item: PRItem, excluding username: String) async throws -> [PRItem.Comment]
    /// Combined build result of a commit.
    func buildState(commit: String) async throws -> BuildState
    /// "OPEN", "MERGED" or "DECLINED", for a PR that left my list.
    func state(projectKey: String, repoSlug: String, number: Int) async throws -> String
}

struct OpenPullRequests {
    var toReview: [PRItem]
    var mine: [PRItem]
    var username: String
}
