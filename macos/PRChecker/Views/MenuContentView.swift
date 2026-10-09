import SwiftUI

struct MenuContentView: View {
    enum Tab: Hashable {
        case review, mine
    }

    @Environment(PRStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab

    init(initialTab: Tab = .review) {
        _tab = State(initialValue: initialTab)
    }

    private var items: [PRItem] { tab == .review ? store.toReview : store.mine }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.listPicker, selection: $tab) {
                Text(L10n.toReviewTab(n: store.toReview.count)).tag(Tab.review)
                Text(L10n.mineTab(n: store.mine.count)).tag(Tab.mine)
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
                    Label(L10n.cantLoadPullRequests, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button(L10n.openSettings, action: openSettings)
                }
            } else if store.lastUpdated == nil {
                ProgressView()
            } else if tab == .review {
                ContentUnavailableView(L10n.nothingToReview, systemImage: "checkmark.circle")
            } else {
                ContentUnavailableView(L10n.noOpenPullRequests, systemImage: "tray")
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
                Button(L10n.notificationsOffMac, systemImage: "bell.slash.fill") {
                    Notifier.shared.openSystemSettings()
                }
                .foregroundStyle(.orange)
                .help(L10n.notificationsOffMacHelp)
            }
            if let last = store.lastUpdated {
                Text(L10n.updatedAgo(time: last.relativeText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button(L10n.refresh, systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r")
            }
            Button(L10n.settings, systemImage: "gearshape", action: openSettings)
                .keyboardShortcut(",")
                .help(L10n.settings)
            Button(L10n.quit, systemImage: "power", action: confirmQuit)
                .keyboardShortcut("q")
                .help(L10n.quitApp)
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

    /// A standalone alert rather than a sheet: the menu bar panel closes when it loses focus.
    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = L10n.quitConfirmTitle
        alert.informativeText = L10n.quitConfirmMessage
        alert.addButton(withTitle: L10n.quit)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
