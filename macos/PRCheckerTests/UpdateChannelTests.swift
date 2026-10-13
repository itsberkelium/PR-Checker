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
}
