import AppKit
import SwiftUI

@main
struct PRCheckerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PRStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("PR Checker Settings", id: SettingsView.windowID) {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(store.isConfigured ? .suppressed : .presented)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.activate()
        if AppSettings.shared.notificationsEnabled {
            Notifier.shared.requestAuthorization()
        }
        PRStore.shared.start()
        Updater.shared.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await PRStore.shared.refresh() }
        }
    }
}

struct MenuBarLabel: View {
    let store: PRStore

    var body: some View {
        let count = store.toReview.count
        let attention = store.mine.contains(where: \.needsAttention)
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.pull")
            if count > 0 || attention {
                Text("\(count)\(attention ? "•" : "")")
            }
        }
    }
}
