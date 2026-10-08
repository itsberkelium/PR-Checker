import Foundation
import Observation

@Observable
final class PRStore {
    static let shared = PRStore(settings: .shared)

    /// Requests in flight at once while fetching comments, builds and PR states.
    static let maxConcurrentRequests = 4
    /// Departed PRs looked up per refresh; any beyond this say "No longer open".
    static let maxStateLookups = 10

    private(set) var reviewItems: [PRItem] = []
    private(set) var mineItems: [PRItem] = []
    private(set) var username: String?
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Bumped whenever the connection changes; results from older generations are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var commentCache: [String: CommentCacheEntry] = [:]
    /// Finished build results by commit; running or missing builds are fetched again.
    @ObservationIgnored private var buildCache: [String: BuildState] = [:]

    private struct CommentCacheEntry {
        let commentCount: Int
        let updated: Date
        let comments: [PRItem.Comment]
    }

    private static let snapshotPrefix = "snapshot.v2|"
    private static let automationPrefix = "automation.v1|"
    private static let legacySnapshotKey = "snapshot"

    init(settings: AppSettings) {
        self.settings = settings
        settings.defaults.removeObject(forKey: Self.legacySnapshotKey)
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

    /// Refreshes, or waits for the refresh already in progress.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh(generation: generation) }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    /// Validates a server and token without saving them. Nothing is sent
    /// anywhere until this runs, and a blank token only reuses the saved one
    /// for the same server. Returns the signed-in user name.
    func connect(serverURL: String, token: String) async throws -> String {
        let client = try settings.draftClient(serverURL: serverURL, token: token)
        let name = try await client.currentUser()
        try settings.applyConnection(client)
        reset()
        start()
        return name
    }

    /// Removes the token, this connection's stored PR state and its delivered notifications.
    func signOut() throws {
        if let server = settings.server {
            for key in settings.defaults.dictionaryRepresentation().keys
            where key.hasPrefix(Self.snapshotPrefix + server.id + "|") || key.hasPrefix(Self.automationPrefix + server.id + "|") {
                settings.defaults.removeObject(forKey: key)
            }
        }
        try settings.signOut()
        reset()
        Notifier.shared.removeDelivered()
        errorMessage = "Signed out. Connect again in Settings → Bitbucket."
    }

    /// Stops in-flight work and forgets everything shown for the previous connection.
    private func reset() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        reviewItems = []
        mineItems = []
        username = nil
        lastUpdated = nil
        errorMessage = nil
        isLoading = false
        commentCache = [:]
        buildCache = [:]
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && !Task.isCancelled
    }

    private func performRefresh(generation: Int) async {
        guard let client = settings.makeClient() else {
            errorMessage = "Add your server URL and access token in Settings."
            return
        }
        isLoading = true
        defer { if generation == self.generation { isLoading = false } }

        do {
            async let reviewing = client.dashboard(role: .reviewer)
            async let authored = client.dashboard(role: .author)
            let (reviewDashboard, authorDashboard) = try await (reviewing, authored)
            guard isCurrent(generation) else { return }

            let me: String
            if let name = reviewDashboard.username ?? authorDashboard.username {
                me = name
            } else {
                me = try await client.whoami()
            }
            guard isCurrent(generation) else { return }

            let server = client.server
            var review = reviewDashboard.pullRequests.compactMap { PRItem(reviewing: $0, as: me, server: server) }
            var mine = authorDashboard.pullRequests.map { PRItem($0, server: server) }
            let rateLimited = await enrich(&review, &mine, client: client, me: me)
            guard isCurrent(generation) else { return }

            username = me
            reviewItems = review.sorted { $0.updated > $1.updated }
            mineItems = mine.sorted { $0.updated > $1.updated }
            lastUpdated = .now
            errorMessage = rateLimited ? APIError.rateLimited.errorDescription : nil
            await notifyChanges(client: client, me: me, generation: generation)
            guard isCurrent(generation) else { return }
            runAutomation(server: client.server, me: me)
        } catch {
            guard isCurrent(generation), !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private enum Job {
        case comments(Int, PRItem)
        case build(String)
    }

    private enum JobResult {
        case comments(Int, [PRItem.Comment]?)
        case build(String, BuildState?)
        case rateLimited
    }

    /// Adds comments by others to every PR and build results to mine, reusing
    /// cached results that can't have changed. Hidden PRs are included so that
    /// widening a filter doesn't re-announce them. Returns whether Bitbucket rate-limited us.
    private func enrich(_ review: inout [PRItem], _ mine: inout [PRItem], client: BitbucketClient, me: String) async -> Bool {
        let all = review + mine
        var jobs: [Job] = []
        for (index, item) in all.enumerated() {
            if let cached = commentCache[item.id], cached.commentCount == item.commentCount, cached.updated == item.updated {
                continue
            }
            jobs.append(.comments(index, item))
        }
        for commit in Set(mine.map(\.latestCommit)) where buildCache[commit] == nil {
            jobs.append(.build(commit))
        }

        let results = await boundedMap(jobs) { job -> JobResult in
            do {
                switch job {
                case .comments(let index, let item):
                    return .comments(index, try await client.commentsByOthers(on: item, excluding: me))
                case .build(let commit):
                    return .build(commit, try await client.buildState(commit: commit))
                }
            } catch APIError.rateLimited {
                return .rateLimited
            } catch {
                switch job {
                case .comments(let index, _): return .comments(index, nil)
                case .build(let commit): return .build(commit, nil)
                }
            }
        }

        var rateLimited = false
        var builds: [String: BuildState] = [:]
        for result in results {
            switch result {
            case .comments(let index, let comments?):
                let item = all[index]
                commentCache[item.id] = CommentCacheEntry(
                    commentCount: item.commentCount, updated: item.updated, comments: comments)
            case .build(let commit, let state?):
                builds[commit] = state
                if state == .passed || state == .failed { buildCache[commit] = state }
            case .rateLimited:
                rateLimited = true
            default:
                break
            }
        }

        // Unknown comments stay nil so the snapshot keeps the previous "last seen" time.
        func apply(_ item: inout PRItem) {
            item.commentsByOthers = commentCache[item.id]?.comments
        }
        for index in review.indices { apply(&review[index]) }
        for index in mine.indices {
            apply(&mine[index])
            mine[index].build = buildCache[mine[index].latestCommit] ?? builds[mine[index].latestCommit] ?? .none
        }

        let liveIDs = Set(all.map(\.id))
        commentCache = commentCache.filter { liveIDs.contains($0.key) }
        let liveCommits = Set(mine.map(\.latestCommit))
        buildCache = buildCache.filter { liveCommits.contains($0.key) }
        return rateLimited
    }

    /// Starts the automation command for review PRs that are new or have new commits. Commits it
    /// already ran for are remembered per server and user; while it's off nothing is recorded,
    /// so turning it on catches up with the current list.
    private func runAutomation(server: ServerAddress, me: String) {
        let command = settings.automationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.automationEnabled, !command.isEmpty else { return }
        let key = automationKey(server: server, me: me)
        let done = Set(settings.defaults.stringArray(forKey: key) ?? [])
        let (items, triggered) = Automation.pending(toReview, alreadyTriggered: done)
        settings.defaults.set(Array(triggered), forKey: key)
        Automation.run(command, for: items)
    }

    private func automationKey(server: ServerAddress, me: String) -> String {
        Self.automationPrefix + server.id + "|" + me.lowercased()
    }

    private var currentAutomationKey: String? {
        guard let server = settings.server, let username else { return nil }
        return automationKey(server: server, me: username)
    }

    /// PRs in To review whose current commit hasn't triggered the command yet.
    var automationBacklog: [PRItem] {
        guard let key = currentAutomationKey else { return [] }
        return Automation.pending(toReview, alreadyTriggered: Set(settings.defaults.stringArray(forKey: key) ?? [])).items
    }

    /// Runs the command for every PR in To review now, including commits it already ran for.
    func runAutomationNow() {
        let command = settings.automationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, let key = currentAutomationKey else { return }
        settings.defaults.set(Array(Automation.pending(toReview, alreadyTriggered: []).triggered), forKey: key)
        Automation.run(command, for: toReview)
    }

    /// Marks the current list as done without running, so only later arrivals trigger the command.
    func skipAutomationBacklog() {
        guard let key = currentAutomationKey else { return }
        settings.defaults.set(Array(Automation.pending(toReview, alreadyTriggered: []).triggered), forKey: key)
    }

    /// Compares against the snapshot saved for this server and user, so restarts
    /// and connection switches don't announce anything that isn't new.
    private func notifyChanges(client: BitbucketClient, me: String, generation: Int) async {
        let key = Self.snapshotPrefix + client.server.id + "|" + me.lowercased()
        let defaults = settings.defaults
        let old = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let new = Snapshot(toReview: reviewItems, mine: mineItems, previous: old, isShown: settings.includes)
        defaults.set(try? JSONEncoder().encode(new), forKey: key)

        guard settings.notificationsEnabled, let old else { return }

        let departed = old.departedMine(in: new).sorted { $0.key < $1.key }.prefix(Self.maxStateLookups)
        let states = await boundedMap(Array(departed)) { id, pr -> (String, String?) in
            (id, try? await client.state(projectKey: pr.projectKey, repoSlug: pr.repoSlug, number: pr.number))
        }
        guard isCurrent(generation) else { return }
        let closedStates = Dictionary(states.compactMap { id, state in state.map { (id, $0) } },
                                      uniquingKeysWith: { first, _ in first })

        let changes = ChangeDetector.changes(
            from: old, to: new, toReview: toReview, mine: mine, closedStates: closedStates
        )
        for change in changes {
            Notifier.shared.post(change)
        }
    }

    /// Runs `operation` over `inputs` with at most `maxConcurrentRequests` in
    /// flight, returning results in input order.
    private func boundedMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], _ operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        var results = [Output?](repeating: nil, count: inputs.count)
        await withTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            func addNext() {
                guard next < inputs.count, !Task.isCancelled else { return }
                let index = next
                let input = inputs[index]
                group.addTask { (index, await operation(input)) }
                next += 1
            }
            for _ in 0..<Self.maxConcurrentRequests { addNext() }
            for await (index, output) in group {
                results[index] = output
                addNext()
            }
        }
        return results.compactMap { $0 }
    }

    #if DEBUG
    /// Shows the given PRs without any network access; for rendering screenshots.
    func showDemoData(review: [PRItem], mine: [PRItem], username: String) {
        reset()
        reviewItems = review
        mineItems = mine
        self.username = username
        lastUpdated = .now.addingTimeInterval(-40)
    }
    #endif

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
