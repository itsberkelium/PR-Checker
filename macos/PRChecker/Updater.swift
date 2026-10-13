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

    /// On a dev build with the stable channel chosen, offers the kept stable version instead:
    /// Sparkle never installs an older version.
    func checkForUpdates() {
        NSApp.activate()
        let running = StableCopy.runningVersion
        guard !AppSettings.shared.devUpdates, StableCopy.isDevBuild(running) else {
            controller.checkForUpdates(nil)
            return
        }
        offerStableVersion(replacing: running)
    }

    /// Going to dev keeps a copy of the stable app first. Going back on a stable build drops the copy;
    /// on a dev build it stays for Check for Updates to restore.
    func setDevChannel(_ dev: Bool) {
        let running = StableCopy.runningVersion
        if dev {
            try? StableCopy.standard.keep(Bundle.main.bundleURL, version: running)
        } else if !StableCopy.isDevBuild(running) {
            StableCopy.standard.discard()
        }
        AppSettings.shared.devUpdates = dev
    }

    private func offerStableVersion(replacing current: String) {
        let copy = StableCopy.standard
        guard let stable = copy.version else {
            let alert = NSAlert()
            alert.messageText = L10n.noStableCopy
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.backToStableTitle
        alert.informativeText = L10n.backToStableMessage(stable: stable, current: current)
        alert.addButton(withTitle: L10n.goBackToStable)
        alert.addButton(withTitle: L10n.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try copy.restore(over: Bundle.main.bundleURL)
            StableCopy.relaunch(Bundle.main.bundleURL)
        } catch {
            let failure = NSAlert()
            failure.messageText = L10n.couldntRestoreStable(message: error.localizedDescription)
            failure.runModal()
        }
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
