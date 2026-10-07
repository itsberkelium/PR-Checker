import SwiftUI

struct MenuContentView: View {
    enum Tab: Hashable {
        case review, mine
    }

    @Environment(PRStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .review

    private var items: [PRItem] { tab == .review ? store.toReview : store.mine }

    var body: some View {
        VStack(spacing: 0) {
            Picker("List", selection: $tab) {
                Text("To review (\(store.toReview.count))").tag(Tab.review)
                Text("Mine (\(store.mine.count))").tag(Tab.mine)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()
            content
                .frame(width: 400, height: 380)
            Divider()
            footer
        }
        .task {
            await Notifier.shared.refreshStatus()
            // Opening the popover with stale data triggers a refresh.
            if let last = store.lastUpdated, last.timeIntervalSinceNow > -60 { return }
            await store.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            if let error = store.errorMessage {
                ContentUnavailableView {
                    Label("Can't load pull requests", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Open Settings", action: openSettings)
                }
            } else if store.lastUpdated == nil {
                ProgressView()
            } else if tab == .review {
                ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle")
            } else {
                ContentUnavailableView("No open pull requests", systemImage: "tray")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        PRRow(item: item, showsAuthor: tab == .review)
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = store.errorMessage, !items.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            }
            if store.settings.notificationsEnabled && Notifier.shared.isBlockedBySystem {
                Button("Notifications are off in System Settings", systemImage: "bell.slash.fill") {
                    Notifier.shared.openSystemSettings()
                }
                .foregroundStyle(.orange)
                .help("Notifications are turned off for PR Checker in System Settings. Click to fix.")
            }
            if let last = store.lastUpdated {
                Text("Updated \(last, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r")
            }
            Menu {
                Button("Settings…", action: openSettings)
                    .keyboardShortcut(",")
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                Divider()
                Button("Quit PR Checker") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Label("More", systemImage: "gearshape")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openSettings() {
        openWindow(id: SettingsView.windowID)
        NSApp.activate()
    }
}
