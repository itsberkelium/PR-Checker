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
        .defaultLaunchBehavior(AppDelegate.isHeadless || store.isConfigured ? .suppressed : .presented)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Hosting unit tests: don't poll, notify or check for updates with the
    /// developer's real settings while tests run.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Launched only to run tests or render screenshots.
    static var isHeadless: Bool {
        #if DEBUG
        isRunningTests || ScreenshotRenderer.isRequested
        #else
        isRunningTests
        #endif
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isHeadless else { return }
        // Before launch finishes, so a click that launched the app still reaches the delegate.
        Notifier.shared.activate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ScreenshotRenderer.isRequested {
            ScreenshotRenderer.renderAndQuit()
            return
        }
        #endif
        guard !Self.isRunningTests else { return }

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
