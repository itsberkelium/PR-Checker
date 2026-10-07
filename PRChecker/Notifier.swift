import AppKit
import Observation
import UserNotifications

/// Posts macOS notifications and opens the PR when one is clicked.
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// What macOS allows, independent of the app's own Notifications toggle.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The user (or an MDM profile) turned PR Checker off in System Settings → Notifications.
    var isBlockedBySystem: Bool { authorizationStatus == .denied }

    @ObservationIgnored private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
        // Pick up changes made in System Settings while the app was running.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await Notifier.shared.refreshStatus() }
        }
        Task { await refreshStatus() }
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshStatus()
        }
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Opens System Settings → Notifications → PR Checker.
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
        NSWorkspace.shared.open(url ?? URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func sendTest() {
        post(Change(
            title: "PR Checker notifications work",
            body: "You'll be notified about review requests and changes to your PRs.",
            url: URL(string: "https://github.com/itsberkelium/PR-Checker")!
        ))
    }

    func post(_ change: Change) {
        let content = UNMutableNotificationContent()
        content.title = change.title
        content.body = change.body
        content.sound = .default
        content.userInfo = ["url": change.url.absoluteString]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: link) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
