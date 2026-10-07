#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `--render-screenshots <dir>` renders the menu with made-up pull
/// requests in light and dark mode, writes PNGs and quits. It uses throwaway
/// settings and never touches the network, the Keychain or real preferences.
enum ScreenshotRenderer {
    private static let flag = "--render-screenshots"

    static var isRequested: Bool { outputDirectory != nil }

    private static var outputDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func renderAndQuit() {
        guard let directory = outputDirectory else { return }
        let suite = "dev.berke.PRChecker.screenshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults, tokens: NoTokens())
        settings.notificationsEnabled = false
        let store = PRStore(settings: settings)
        store.showDemoData(review: DemoData.review, mine: DemoData.mine, username: "sam.reviewer")

        Task {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for (tab, tabName) in [(MenuContentView.Tab.review, "review"), (.mine, "mine")] {
                    for (appearance, appearanceName) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                        let file = directory.appending(component: "menu-\(tabName)-\(appearanceName).png")
                        try await render(MenuContentView(initialTab: tab).environment(store), appearance: appearance, to: file)
                        print("Wrote \(file.path)")
                    }
                }
                defaults.removePersistentDomain(forName: suite)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Screenshot rendering failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    private struct RenderError: Error {}

    private static func render(_ view: some View, appearance: NSAppearance.Name, to file: URL) async throws {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let framed = view
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor)))
        let host = NSHostingView(rootView: framed)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance)
        window.alphaValue = 0 // rendered offscreen into a bitmap, never visible
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        try await Task.sleep(for: .milliseconds(700)) // let SwiftUI lay out and draw
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError() }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError() }
        try png.write(to: file)
    }

    private struct NoTokens: TokenStore {
        func read(account: String) -> String? { nil }
        func save(_ token: String, account: String) throws {}
        func delete(account: String) throws {}
    }
}

/// Made-up pull requests. Names, projects and titles are fictional.
private enum DemoData {
    static let server = try! ServerAddress(parsing: "https://bitbucket.example.com")

    static let review: [PRItem] = [
        pr(41, "Add retry with backoff to payment webhooks", project: "PAY", repo: "payments-api", name: "Payments API",
           from: "feature/webhook-retries", author: "Priya Natarajan", minutesAgo: 12,
           reviewers: [("Sam Reviewer", .unapproved), ("Jordan Lee", .approved)], comments: 3, newCommits: true),
        pr(318, "Migrate settings screen to SwiftUI", project: "MOB", repo: "mobile-app", name: "Mobile App",
           from: "feature/swiftui-settings", author: "Mateo García", minutesAgo: 64,
           reviewers: [("Sam Reviewer", .unapproved), ("Alex Kim", .unapproved)], comments: 5, tasks: 1),
        pr(1204, "Fix crash when opening an empty project", project: "WEB", repo: "web-app", name: "Web App",
           from: "bugfix/empty-project-crash", author: "Alex Kim", minutesAgo: 190,
           reviewers: [("Sam Reviewer", .unapproved), ("Priya Natarajan", .approved)]),
        pr(1198, "Update German translations", project: "WEB", repo: "web-app", name: "Web App",
           from: "l10n/de", author: "Jordan Lee", minutesAgo: 1_500,
           reviewers: [("Sam Reviewer", .unapproved)], comments: 1),
    ]

    static let mine: [PRItem] = [
        pr(1207, "Cache avatar images on disk", project: "WEB", repo: "web-app", name: "Web App",
           from: "feature/avatar-cache", author: "Sam Reviewer", minutesAgo: 25,
           reviewers: [("Alex Kim", .approved), ("Jordan Lee", .approved)], comments: 2, build: .passed),
        pr(322, "Rework onboarding flow", project: "MOB", repo: "mobile-app", name: "Mobile App",
           from: "feature/onboarding-v2", author: "Sam Reviewer", minutesAgo: 140,
           reviewers: [("Mateo García", .needsWork), ("Priya Natarajan", .unapproved)],
           comments: 7, tasks: 2, build: .failed, conflicts: true),
        pr(44, "Bump dependencies to latest minor versions", project: "PAY", repo: "payments-api", name: "Payments API",
           from: "chore/deps", author: "Sam Reviewer", minutesAgo: 300,
           reviewers: [("Priya Natarajan", .approved), ("Jordan Lee", .unapproved), ("Alex Kim", .unapproved)],
           build: .running),
    ]

    private static func pr(
        _ number: Int, _ title: String, project: String, repo: String, name: String, from: String,
        author: String, minutesAgo: Double, reviewers: [(String, ReviewStatus)],
        comments: Int = 0, tasks: Int = 0, build: BuildState = .none,
        conflicts: Bool = false, newCommits: Bool = false
    ) -> PRItem {
        var item = PRItem(
            id: "\(project)/\(repo)#\(number)", number: number, title: title,
            projectKey: project, repoSlug: repo, repoName: name,
            sourceBranch: from, targetBranch: "main", authorName: author,
            url: server.pullRequestURL(projectKey: project, repoSlug: repo, number: number),
            updated: .now.addingTimeInterval(-minutesAgo * 60), isDraft: false, latestCommit: "\(number)",
            reviewers: reviewers.map { PRItem.Reviewer(name: $0.0, status: $0.1) },
            hasConflicts: conflicts, commentCount: comments, openTaskCount: tasks
        )
        item.build = build
        item.hasNewCommits = newCommits
        return item
    }
}
#endif
