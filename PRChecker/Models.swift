import Foundation

// MARK: - Bitbucket Server REST payloads

struct Page<Value: Decodable>: Decodable {
    let values: [Value]
    let isLastPage: Bool
    let nextPageStart: Int?
}

struct PullRequest: Decodable {
    let id: Int
    let title: String
    let draft: Bool?
    let updatedDate: Int64
    let fromRef: Ref
    let toRef: Ref
    let author: Participant
    let reviewers: [Participant]
    let properties: Properties?

    struct Ref: Decodable {
        let displayId: String
        let latestCommit: String
        let repository: Repository
    }

    struct Repository: Decodable {
        let slug: String
        let name: String
        let project: Project
    }

    struct Project: Decodable {
        let key: String
    }

    struct User: Decodable {
        let name: String
        let slug: String
        let displayName: String?

        func isSameUser(as username: String) -> Bool {
            name.caseInsensitiveCompare(username) == .orderedSame
                || slug.caseInsensitiveCompare(username) == .orderedSame
        }
    }

    struct Participant: Decodable {
        let user: User
        let status: ReviewStatus
        let lastReviewedCommit: String?
    }

    struct Properties: Decodable {
        let mergeResult: MergeResult?
        let commentCount: Int?
        let openTaskCount: Int?
    }

    struct MergeResult: Decodable {
        let outcome: String
    }

}

enum ReviewStatus: String, Codable, Sendable {
    case approved = "APPROVED"
    case unapproved = "UNAPPROVED"
    case needsWork = "NEEDS_WORK"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReviewStatus(rawValue: raw) ?? .unapproved
    }
}

struct Activity: Decodable {
    let id: Int
    let createdDate: Int64
    let action: String
    let commentAction: String?
    let user: PullRequest.User
}

struct PullRequestState: Decodable {
    let state: String
}

struct BuildStats: Decodable {
    let successful: Int?
    let failed: Int?
    let inProgress: Int?
}

// MARK: - App model

enum BuildState: String, Codable, Sendable {
    case none, running, passed, failed
}

struct PRItem: Identifiable, Equatable {
    struct Reviewer: Hashable {
        let name: String
        let status: ReviewStatus
    }

    struct Comment: Hashable {
        let id: Int
        /// Milliseconds since 1970. Activity IDs aren't chronological, so "new" is decided by time.
        let created: Int64
        let author: String
    }

    /// Unique across repositories, e.g. "PROJ/web-app#42".
    let id: String
    let number: Int
    let title: String
    let projectKey: String
    let repoSlug: String
    let repoName: String
    let sourceBranch: String
    let targetBranch: String
    let authorName: String
    let url: URL
    let updated: Date
    let isDraft: Bool
    let latestCommit: String
    let reviewers: [Reviewer]
    let hasConflicts: Bool
    let commentCount: Int
    let openTaskCount: Int
    var build: BuildState = .none
    /// Review list only: the author pushed commits after my last review.
    var hasNewCommits = false
    /// Recent comments and replies by people other than me; nil when they couldn't be fetched.
    var commentsByOthers: [Comment]?

    var approvals: Int { reviewers.filter { $0.status == .approved }.count }
    var needsWork: Bool { reviewers.contains { $0.status == .needsWork } }
    /// Something on my own PR I should act on.
    var needsAttention: Bool { needsWork || hasConflicts || build == .failed || openTaskCount > 0 }
}

extension PRItem {
    /// The link is built from the configured server, never taken from the API response.
    init(_ pr: PullRequest, server: ServerAddress) {
        let repo = pr.toRef.repository
        self.init(
            id: "\(repo.project.key)/\(repo.slug)#\(pr.id)",
            number: pr.id,
            title: pr.title,
            projectKey: repo.project.key,
            repoSlug: repo.slug,
            repoName: repo.name,
            sourceBranch: pr.fromRef.displayId,
            targetBranch: pr.toRef.displayId,
            authorName: pr.author.user.displayName ?? pr.author.user.name,
            url: server.pullRequestURL(projectKey: repo.project.key, repoSlug: repo.slug, number: pr.id),
            updated: Date(timeIntervalSince1970: TimeInterval(pr.updatedDate) / 1000),
            isDraft: pr.draft ?? false,
            latestCommit: pr.fromRef.latestCommit,
            reviewers: pr.reviewers.map { Reviewer(name: $0.user.displayName ?? $0.user.name, status: $0.status) },
            hasConflicts: pr.properties?.mergeResult?.outcome == "CONFLICTED",
            commentCount: pr.properties?.commentCount ?? 0,
            openTaskCount: pr.properties?.openTaskCount ?? 0
        )
    }

    /// Builds a review-list item, or nil when the PR doesn't need my attention:
    /// already approved, or marked needs-work with no new commits since.
    init?(reviewing pr: PullRequest, as username: String, server: ServerAddress) {
        guard let me = pr.reviewers.first(where: { $0.user.isSameUser(as: username) }) else { return nil }
        var item = PRItem(pr, server: server)
        let pushedSinceReview = me.lastReviewedCommit.map { $0 != pr.fromRef.latestCommit } ?? false
        switch me.status {
        case .approved:
            return nil
        case .needsWork:
            guard pushedSinceReview else { return nil }
        case .unapproved:
            break
        }
        item.hasNewCommits = pushedSinceReview
        self = item
    }
}
