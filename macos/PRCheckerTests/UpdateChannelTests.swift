import Foundation
import Sparkle
import Testing
@testable import PR_Checker

@MainActor
struct UpdateChannelTests {
    @Test func testChannelIsOptIn() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, tokens: MemoryTokenStore())
        #expect(!settings.usesTestUpdates)
        defaults.set("test", forKey: "updateChannel")
        #expect(settings.usesTestUpdates)
        defaults.set("release", forKey: "updateChannel")
        #expect(!settings.usesTestUpdates)
    }

    @Test func testFeedSitsNextToTheReleaseFeed() {
        #expect(Updater.testFeedURL(for: "https://cdn.example.com/pr-checker/appcast.xml")
                == "https://cdn.example.com/pr-checker/test/appcast.xml")
    }

    /// Test builds are versioned like 0.3.0b1 (package.sh --publish-test): newer than the last
    /// release, older than the release they lead up to, and in order among themselves.
    /// Sparkle reads "0.3.0-test.1" as equal to 0.3.0, so that form can't be used.
    @Test func testBuildVersionsSortBetweenReleases() {
        let comparator = SUStandardVersionComparator.default
        func older(_ a: String, _ b: String) -> Bool { comparator.compareVersion(a, toVersion: b) == .orderedAscending }
        #expect(older("0.2.9", "0.3.0b1"))
        #expect(older("0.3.0b1", "0.3.0b2"))
        #expect(older("0.3.0b2", "0.3.0b10"))
        #expect(older("0.3.0b10", "0.3.0"))
    }
}
