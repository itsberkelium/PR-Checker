import AppKit
import Sparkle

/// Sparkle auto-updates: checks the appcast weekly (SUScheduledCheckInterval) and asks before installing.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self
    )

    func start() {
        _ = controller
    }

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
