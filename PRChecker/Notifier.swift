import AppKit
import UserNotifications

/// Posts macOS notifications and opens the PR when one is clicked.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
