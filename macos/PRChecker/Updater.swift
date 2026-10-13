import AppKit
import Sparkle

/// Sparkle auto-updates: checks the appcast weekly (SUScheduledCheckInterval) and asks before installing.
/// With `AppSettings.devUpdates`, the feed is the dev appcast next to the release one,
/// where dev builds are published before a release (see macos/README.md).
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: self
    )

    /// "…/pr-checker/appcast.xml" becomes "…/pr-checker/dev/appcast.xml".
    static func devFeedURL(for releaseFeed: String) -> String? {
        guard let url = URL(string: releaseFeed) else { return nil }
        return url.deletingLastPathComponent().appending(path: "dev/appcast.xml").absoluteString
    }

    /// Asked before every check, so changing the channel takes effect without a restart.
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard AppSettings.shared.devUpdates,
              let releaseFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return nil }
        return Self.devFeedURL(for: releaseFeed)
    }

    func start() {
        _ = controller
    }

    /// When Sparkle last checked the feed, automatically or by hand.
    var lastCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // A menu bar app has no Dock icon or windows in front, so bring Sparkle's
    // "new version available" window forward when a scheduled check finds one.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        NSApp.activate()
    }
}
