import Foundation
import Observation

@Observable
final class PRStore {
    static let shared = PRStore(settings: .shared)

    private(set) var reviewItems: [PRItem] = []
    private(set) var mineItems: [PRItem] = []
    private(set) var username: String?
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let snapshotKey = "snapshot"

    init(settings: AppSettings) {
        self.settings = settings
    }

    var toReview: [PRItem] { reviewItems.filter(settings.includes) }
    var mine: [PRItem] { mineItems.filter(settings.includes) }
    var isConfigured: Bool { settings.makeClient() != nil }

    /// (Re)starts polling at the configured interval, refreshing immediately.
    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.settings.refreshMinutes * 60))
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        guard let client = settings.makeClient() else {
            errorMessage = "Add your server URL and access token in Settings."
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            async let reviewing = client.dashboard(role: .reviewer)
            async let authored = client.dashboard(role: .author)
            let (reviewDashboard, authorDashboard) = try await (reviewing, authored)

            let me: String
            if let name = reviewDashboard.username ?? authorDashboard.username {
                me = name
            } else {
                me = try await client.whoami()
            }

            let review = await enriched(
                reviewDashboard.pullRequests.compactMap { PRItem(reviewing: $0, as: me) },
                client: client, me: me, includeBuilds: false
            )
            let mine = await enriched(
                authorDashboard.pullRequests.compactMap(PRItem.init),
                client: client, me: me, includeBuilds: true
            )

            username = me
            reviewItems = review.sorted { $0.updated > $1.updated }
            mineItems = mine.sorted { $0.updated > $1.updated }
            lastUpdated = .now
            errorMessage = nil
            await notifyChanges(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds comments by others (and build results for my PRs). A failed lookup
    /// leaves the field empty rather than failing the whole refresh.
    private func enriched(_ items: [PRItem], client: BitbucketClient, me: String, includeBuilds: Bool) async -> [PRItem] {
        var items = items
        let snapshot = items
        await withTaskGroup(of: (Int, BuildState?, [PRItem.Comment]?).self) { group in
            for (index, item) in snapshot.enumerated() {
                group.addTask {
                    async let comments = try? client.commentsByOthers(on: item, excluding: me)
                    let build = includeBuilds ? ((try? await client.buildState(commit: item.latestCommit)) ?? BuildState.none) : nil
                    return (index, build, await comments)
                }
            }
            for await (index, build, comments) in group {
                if let build { items[index].build = build }
                items[index].commentsByOthers = comments
            }
        }
        return items
    }

    /// Compares against the last saved snapshot so restarts don't re-announce everything.
    private func notifyChanges(client: BitbucketClient) async {
        let defaults = UserDefaults.standard
        let old = defaults.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let new = Snapshot(toReview: reviewItems, mine: mineItems, previous: old, isShown: settings.includes)
        defaults.set(try? JSONEncoder().encode(new), forKey: snapshotKey)

        guard settings.notificationsEnabled, let old else { return }

        var closedStates: [String: String] = [:]
        for (id, pr) in old.departedMine(in: new) {
            closedStates[id] = try? await client.state(projectKey: pr.projectKey, repoSlug: pr.repoSlug, number: pr.number)
        }
        let changes = ChangeDetector.changes(
            from: old, to: new, toReview: toReview, mine: mine, closedStates: closedStates
        )
        for change in changes {
            Notifier.shared.post(change)
        }
    }
}
