import Foundation
import Testing
@testable import PR_Checker

@MainActor
struct ReviewFilterTests {
    @Test func hidesApprovedPRs() throws {
        let pr = try makePR(myStatus: "APPROVED", lastReviewed: "abc", latest: "abc")
        #expect(PRItem(reviewing: pr, as: "sam.reviewer", server: testServer) == nil)
    }

    @Test func showsUnapprovedPRs() throws {
        let pr = try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "abc")
        let item = try #require(PRItem(reviewing: pr, as: "Sam.Reviewer", server: testServer))
        #expect(item.id == "PROJ/web-app#2583")
        #expect(!item.hasNewCommits)
    }

    @Test func needsWorkReappearsOnlyAfterNewCommits() throws {
        let unchanged = try makePR(myStatus: "NEEDS_WORK", lastReviewed: "abc", latest: "abc")
        #expect(PRItem(reviewing: unchanged, as: "sam.reviewer", server: testServer) == nil)

        let pushed = try makePR(myStatus: "NEEDS_WORK", lastReviewed: "abc", latest: "def")
        let item = try #require(PRItem(reviewing: pushed, as: "sam.reviewer", server: testServer))
        #expect(item.hasNewCommits)
    }

    @Test func parsesStatusDetails() throws {
        let item = PRItem(try makePR(myStatus: "APPROVED", lastReviewed: nil, latest: "abc", merge: "CONFLICTED"), server: testServer)
        #expect(item.hasConflicts)
        #expect(item.approvals == 1)
        #expect(item.commentCount == 3)
        #expect(item.needsAttention)
    }
}

@MainActor
struct ChangeDetectorTests {
    private func item(_ status: String = "UNAPPROVED", merge: String = "CLEAN", build: BuildState = .none,
                      comments: [PRItem.Comment]? = []) throws -> PRItem {
        var item = PRItem(try makePR(myStatus: status, lastReviewed: nil, latest: "a", merge: merge), server: testServer)
        item.build = build
        item.commentsByOthers = comments
        return item
    }

    private func snapshot(review: [PRItem] = [], mine: [PRItem] = [], previous: Snapshot? = nil) -> Snapshot {
        Snapshot(toReview: review, mine: mine, previous: previous, isShown: { _ in true })
    }

    @Test func announcesNewReviewRequests() throws {
        let review = try #require(PRItem(reviewing: try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "a"), as: "sam.reviewer", server: testServer))
        let old = snapshot()
        let new = snapshot(review: [review], previous: old)
        let changes = ChangeDetector.changes(from: old, to: new, toReview: [review], mine: [])
        #expect(changes.map(\.title) == ["Review requested by Alex Author"])
    }

    @Test func announcesStatusChangesOnMyPR() throws {
        let before = try item(build: .failed, comments: [.init(id: 10, created: 10, author: "Ali")])
        let after = try item("APPROVED", merge: "CONFLICTED", build: .passed,
                             comments: [.init(id: 12, created: 12, author: "Veli"), .init(id: 11, created: 11, author: "Ali"), .init(id: 10, created: 10, author: "Ali")])
        let old = snapshot(mine: [before])
        let new = snapshot(mine: [after], previous: old)
        let body = try #require(ChangeDetector.changes(from: old, to: new, toReview: [], mine: [after]).first?.body)

        #expect(body.contains("Approved by Sam Reviewer"))
        #expect(body.contains("Merge conflicts"))
        #expect(body.contains("Build fixed"))
        #expect(body.contains("💬 2 new comments from Ali, Veli"))
    }

    @Test func runningBuildKeepsLastResult() throws {
        let failed = snapshot(mine: [try item(build: .failed)])
        let running = snapshot(mine: [try item(build: .running)], previous: failed)
        #expect(running.mine.values.first?.settledBuild == .failed)

        let passedItem = try item(build: .passed)
        let passed = snapshot(mine: [passedItem], previous: running)
        let body = ChangeDetector.changes(from: running, to: passed, toReview: [], mine: [passedItem]).first?.body
        #expect(body == "✅ Build fixed")
    }

    @Test func announcesNewCommentsOnPRsIReview() throws {
        var review = try #require(PRItem(reviewing: try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "a"), as: "sam.reviewer", server: testServer))
        review.commentsByOthers = [.init(id: 5, created: 5, author: "Ali")]
        let old = snapshot(review: [review])
        // Activity IDs aren't chronological: the newer comment has the lower ID.
        review.commentsByOthers = [.init(id: 2, created: 7, author: "Alex Author"), .init(id: 5, created: 5, author: "Ali")]
        let new = snapshot(review: [review], previous: old)

        let changes = ChangeDetector.changes(from: old, to: new, toReview: [review], mine: [])
        #expect(changes.map(\.body) == ["💬 1 new comment from Alex Author"])
    }

    @Test func announcesMergedPRs() throws {
        let old = snapshot(mine: [try item()])
        let new = snapshot(previous: old)
        let changes = ChangeDetector.changes(from: old, to: new, toReview: [], mine: [],
                                             closedStates: ["PROJ/web-app#2583": "MERGED"])
        #expect(changes.map(\.body) == ["🎉 Merged"])
    }

    @Test func widenedFilterDoesNotReannounce() throws {
        let review = try #require(PRItem(reviewing: try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "a"), as: "sam.reviewer", server: testServer))
        // Last refresh tracked the PR while a filter hid it; now it's visible.
        let old = Snapshot(toReview: [review], mine: [], previous: nil, isShown: { _ in false })
        let new = snapshot(review: [review], previous: old)
        #expect(ChangeDetector.changes(from: old, to: new, toReview: [review], mine: []).isEmpty)
    }

    @Test func staysQuietWhenNothingChanged() throws {
        let mine = try item(comments: [.init(id: 3, created: 3, author: "Ali")])
        let old = snapshot(review: [mine], mine: [mine])
        let new = snapshot(review: [mine], mine: [mine], previous: old)
        #expect(ChangeDetector.changes(from: old, to: new, toReview: [mine], mine: [mine]).isEmpty)
    }
}

@MainActor
struct SettingsFilterTests {
    @Test func filtersByProjectOrRepo() throws {
        // A fixed name: macOS keeps an empty plist per suite, so random names would pile up.
        let suite = "dev.berke.PRCheckerTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, tokens: MemoryTokenStore())
        let item = PRItem(try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "a"), server: testServer)

        #expect(settings.includes(item))
        settings.repoFilter = "proj"
        #expect(settings.includes(item))
        settings.repoFilter = "OTHER, PROJ/web-app"
        #expect(settings.includes(item))
        settings.repoFilter = "PROJ/other-repo"
        #expect(!settings.includes(item))
    }
}

// MARK: - Fixtures

let testServer = try! ServerAddress(parsing: "https://bitbucket.example.com")

func makePR(
    myStatus: String,
    lastReviewed: String?,
    latest: String,
    merge: String = "CLEAN",
    comments: Int = 3
) throws -> PullRequest {
    let lastReviewedJSON = lastReviewed.map { "\"\($0)\"" } ?? "null"
    let json = """
    {
      "id": 2583,
      "title": "Add date option to payment form",
      "draft": false,
      "updatedDate": 1791266000000,
      "fromRef": {"displayId": "feature/payment-date", "latestCommit": "\(latest)",
        "repository": {"slug": "web-app", "name": "Web App", "project": {"key": "PROJ"}}},
      "toRef": {"displayId": "test", "latestCommit": "zzz",
        "repository": {"slug": "web-app", "name": "Web App", "project": {"key": "PROJ"}}},
      "author": {"user": {"name": "Alex.Author", "slug": "alex.author", "displayName": "Alex Author"},
        "status": "UNAPPROVED", "lastReviewedCommit": null},
      "reviewers": [{"user": {"name": "Sam.Reviewer", "slug": "sam.reviewer", "displayName": "Sam Reviewer"},
        "status": "\(myStatus)", "lastReviewedCommit": \(lastReviewedJSON)}],
      "properties": {"mergeResult": {"outcome": "\(merge)"}, "commentCount": \(comments), "openTaskCount": 0},
      "links": {"self": [{"href": "file:///etc/passwd"}]}
    }
    """
    return try JSONDecoder().decode(PullRequest.self, from: Data(json.utf8))
}
