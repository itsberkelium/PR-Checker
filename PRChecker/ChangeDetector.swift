import Foundation

/// What we remember between refreshes to decide what's worth a notification.
/// Covers every open PR, not just the ones the filters show, so changing a
/// filter never makes old PRs look new.
struct Snapshot: Codable, Equatable {
    struct Reviewing: Codable, Equatable {
        var lastCommentDate: Int64
    }

    struct Mine: Codable, Equatable {
        var title: String
        var url: URL
        var projectKey: String
        var repoSlug: String
        var number: Int
        /// Whether the filters showed it; departures of hidden PRs aren't announced.
        var shown: Bool
        var approvedBy: Set<String>
        var needsWorkBy: Set<String>
        var conflicted: Bool
        /// Last finished build result; a running build keeps the previous one.
        var settledBuild: BuildState
        var lastCommentDate: Int64
    }

    var reviewing: [String: Reviewing] = [:]
    var mine: [String: Mine] = [:]

    init(toReview: [PRItem], mine: [PRItem], previous: Snapshot?, isShown: (PRItem) -> Bool) {
        for item in toReview {
            let before = previous?.reviewing[item.id]?.lastCommentDate
            reviewing[item.id] = Reviewing(lastCommentDate: Self.lastCommentDate(item, before: before))
        }
        for item in mine {
            let before = previous?.mine[item.id]
            self.mine[item.id] = Mine(
                title: item.title,
                url: item.url,
                projectKey: item.projectKey,
                repoSlug: item.repoSlug,
                number: item.number,
                shown: isShown(item),
                approvedBy: Set(item.reviewers.filter { $0.status == .approved }.map(\.name)),
                needsWorkBy: Set(item.reviewers.filter { $0.status == .needsWork }.map(\.name)),
                conflicted: item.hasConflicts,
                settledBuild: item.build == .running ? (before?.settledBuild ?? .none) : item.build,
                lastCommentDate: Self.lastCommentDate(item, before: before?.lastCommentDate)
            )
        }
    }

    /// Open PRs of mine that were shown last time and are gone now.
    func departedMine(in new: Snapshot) -> [String: Mine] {
        mine.filter { id, state in state.shown && new.mine[id] == nil }
    }

    private static func lastCommentDate(_ item: PRItem, before: Int64?) -> Int64 {
        let latest = item.commentsByOthers?.map(\.created).max() ?? 0
        return max(latest, before ?? 0)
    }
}

struct Change: Equatable {
    let title: String
    let body: String
    let url: URL
}

enum ChangeDetector {
    /// One notification per PR that's new to review or whose state changed.
    /// `toReview` and `mine` are the filtered lists; only those get announced.
    /// `closedStates` maps departed PR IDs to "MERGED"/"DECLINED" when known.
    static func changes(
        from old: Snapshot,
        to new: Snapshot,
        toReview: [PRItem],
        mine: [PRItem],
        closedStates: [String: String] = [:]
    ) -> [Change] {
        var changes: [Change] = []

        for item in toReview {
            guard let before = old.reviewing[item.id] else {
                let title = item.hasNewCommits ? "New commits to re-review" : "Review requested by \(item.authorName)"
                changes.append(Change(title: title, body: item.title, url: item.url))
                continue
            }
            if let line = commentLine(item, after: before.lastCommentDate) {
                changes.append(Change(title: item.title, body: line, url: item.url))
            }
        }

        for item in mine {
            guard let before = old.mine[item.id], let after = new.mine[item.id] else { continue }
            var lines: [String] = []
            for name in after.approvedBy.subtracting(before.approvedBy).sorted() {
                lines.append("✅ Approved by \(name)")
            }
            for name in after.needsWorkBy.subtracting(before.needsWorkBy).sorted() {
                lines.append("✋ \(name) marked it needs work")
            }
            if after.conflicted != before.conflicted {
                lines.append(after.conflicted ? "⚠️ Merge conflicts" : "🔧 Conflicts resolved")
            }
            if after.settledBuild != before.settledBuild {
                if after.settledBuild == .failed { lines.append("❌ Build failed") }
                if after.settledBuild == .passed && before.settledBuild == .failed { lines.append("✅ Build fixed") }
            }
            if let line = commentLine(item, after: before.lastCommentDate) {
                lines.append(line)
            }
            if !lines.isEmpty {
                changes.append(Change(title: item.title, body: lines.joined(separator: "\n"), url: item.url))
            }
        }

        for (id, state) in old.departedMine(in: new).sorted(by: { $0.key < $1.key }) {
            let body = switch closedStates[id] {
            case "MERGED": "🎉 Merged"
            case "DECLINED": "🚫 Declined"
            default: "No longer open"
            }
            changes.append(Change(title: state.title, body: body, url: state.url))
        }
        return changes
    }

    private static func commentLine(_ item: PRItem, after lastSeen: Int64) -> String? {
        let fresh = (item.commentsByOthers ?? []).filter { $0.created > lastSeen }
        guard !fresh.isEmpty else { return nil }
        var authors: [String] = []
        for comment in fresh.sorted(by: { $0.created < $1.created }) where !authors.contains(comment.author) {
            authors.append(comment.author)
        }
        let noun = fresh.count == 1 ? "comment" : "comments"
        return "💬 \(fresh.count) new \(noun) from \(authors.joined(separator: ", "))"
    }
}
