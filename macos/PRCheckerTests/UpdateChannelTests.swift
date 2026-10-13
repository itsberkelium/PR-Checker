import Foundation
import Sparkle
import Testing
@testable import PR_Checker

@MainActor
struct UpdateChannelTests {
    @Test func devChannelIsOptInAndRemembered() {
        let defaults = freshDefaults()
        #expect(!AppSettings(defaults: defaults, tokens: MemoryTokenStore()).devUpdates)
        AppSettings(defaults: defaults, tokens: MemoryTokenStore()).devUpdates = true
        #expect(defaults.string(forKey: "updateChannel") == "dev")
        let reloaded = AppSettings(defaults: defaults, tokens: MemoryTokenStore())
        #expect(reloaded.devUpdates)
        reloaded.devUpdates = false
        #expect(defaults.string(forKey: "updateChannel") == nil)
    }

    @Test func devFeedSitsNextToTheReleaseFeed() {
        #expect(Updater.devFeedURL(for: "https://cdn.example.com/pr-checker/appcast.xml")
                == "https://cdn.example.com/pr-checker/dev/appcast.xml")
    }

    /// Dev builds are versioned like 0.3.0d1 (package.sh --publish-dev): newer than the last
    /// release, older than the release they lead up to, and in order among themselves.
    /// Sparkle reads "0.3.0-dev.1" as equal to 0.3.0, so that form can't be used.
    @Test func devBuildVersionsSortBetweenReleases() {
        let comparator = SUStandardVersionComparator.default
        func older(_ a: String, _ b: String) -> Bool { comparator.compareVersion(a, toVersion: b) == .orderedAscending }
        #expect(older("0.2.9", "0.3.0d1"))
        #expect(older("0.3.0d1", "0.3.0d2"))
        #expect(older("0.3.0d2", "0.3.0d10"))
        #expect(older("0.3.0d10", "0.3.0"))
        #expect(comparator.compareVersion("0.3.0-dev.1", toVersion: "0.3.0") == .orderedSame)
    }

    // MARK: Going back to stable on macOS

    @Test func recognizesDevBuilds() {
        #expect(StableCopy.isDevBuild("0.3.0d1"))
        #expect(StableCopy.isDevBuild("1.10.2d12"))
        #expect(!StableCopy.isDevBuild("0.2.9"))
        #expect(!StableCopy.isDevBuild("0.3.0b1"))
        #expect(!StableCopy.isDevBuild("0.3.0d"))
    }

    /// A folder with a fake app ("PR Checker.app" with an Info.plist) and where to keep its copy.
    private func sandbox() throws -> (root: URL, copy: StableCopy) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var copy = StableCopy(url: root.appending(path: "Support/Stable/PR Checker.app"))
        copy.verify = { _ in }
        return (root, copy)
    }

    private func makeApp(at url: URL, version: String) throws {
        let contents = url.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version],
                                                       format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
    }

    @Test func keepsOnlyStableBuilds() throws {
        let (root, copy) = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Applications/PR Checker.app")

        try makeApp(at: app, version: "0.2.9")
        try copy.keep(app, version: "0.2.9")
        #expect(copy.version == "0.2.9")

        // Turning dev on again from a dev build keeps the stable copy already there.
        try FileManager.default.removeItem(at: app)
        try makeApp(at: app, version: "0.3.0d1")
        try copy.keep(app, version: "0.3.0d1")
        #expect(copy.version == "0.2.9")

        // A newer stable build replaces it.
        try FileManager.default.removeItem(at: app)
        try makeApp(at: app, version: "0.3.0")
        try copy.keep(app, version: "0.3.0")
        #expect(copy.version == "0.3.0")
    }

    @Test func restorePutsTheStableCopyBack() throws {
        let (root, copy) = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Applications/PR Checker.app")
        try makeApp(at: app, version: "0.2.9")
        try copy.keep(app, version: "0.2.9")
        try FileManager.default.removeItem(at: app)
        try makeApp(at: app, version: "0.3.0d1")

        try copy.restore(over: app)
        #expect(StableCopy.version(of: app) == "0.2.9")
        #expect(copy.version == nil)
    }

    @Test func restoreRefusesAnUnsignedCopy() throws {
        var (root, copy) = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        copy.verify = StableCopy.verifySignature
        let app = root.appending(path: "Applications/PR Checker.app")
        try makeApp(at: app, version: "0.2.9")
        try copy.keep(app, version: "0.2.9")
        try FileManager.default.removeItem(at: app)
        try makeApp(at: app, version: "0.3.0d1")

        #expect(throws: (any Error).self) { try copy.restore(over: app) }
        #expect(StableCopy.version(of: app) == "0.3.0d1")
        #expect(copy.version == "0.2.9")
    }
}
