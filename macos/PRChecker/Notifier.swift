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
    @ObservationIgnored private var isActive = false

    func activate() {
        guard !isActive else { return }
        isActive = true
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

    /// Has no link, so clicking it just dismisses it.
    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = L10n.testNotificationTitle
        content.body = L10n.testNotificationBody
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func post(_ change: Change) {
        let content = UNMutableNotificationContent()
        if AppSettings.shared.notificationDetails {
            content.title = change.title
            content.body = change.body
        } else {
            // No titles, names or outcomes, e.g. for screen sharing or a locked screen.
            content.title = "PR Checker"
            content.body = L10n.privateNotificationBody
        }
        content.sound = .default
        content.userInfo = ["url": change.url.absoluteString]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Clears PR Checker's notifications from Notification Center.
    func removeDelivered() {
        center.removeAllDeliveredNotifications()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Clicking the notification opens the PR (macOS removes it); closing it does nothing.
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let link = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: link) {
            Task { @MainActor in Self.open(url) }
        }
        completionHandler()
    }

    /// Opens a PR link only if it points at the configured server; stored
    /// links are checked again because the server may have changed since.
    static func open(_ url: URL) {
        guard AppSettings.shared.server?.owns(url) == true else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
