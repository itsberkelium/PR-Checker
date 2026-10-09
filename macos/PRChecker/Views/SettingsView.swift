import ServiceManagement
import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    enum Tab: Hashable {
        case general, bitbucket, about
    }

    @Environment(PRStore.self) private var store
    @State private var tab: Tab = PRStore.shared.isConfigured ? .general : .bitbucket

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label(L10n.tabGeneral, systemImage: "gearshape") }
                .tag(Tab.general)
            BitbucketSettings()
                .tabItem { Label(L10n.tabBitbucket, systemImage: "server.rack") }
                .tag(Tab.bitbucket)
            AboutSettings()
                .tabItem { Label(L10n.tabAbout, systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(PRStore.self) private var store
    private let notifier = Notifier.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = store.settings

        Form {
            Section(L10n.tabGeneral) {
                Toggle(L10n.notifications, isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled {
                    if notifier.isBlockedBySystem {
                        LabeledContent {
                            Button(L10n.openNotificationSettings) { notifier.openSystemSettings() }
                        } label: {
                            Label {
                                Text(L10n.blockedMacTitle)
                                Text(L10n.blockedMacMessage)
                            } icon: {
                                Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                            }
                        }
                    } else {
                        LabeledContent(L10n.checkDelivery) {
                            Button(L10n.sendTestNotification) { notifier.sendTest() }
                        }
                    }
                    Toggle(isOn: $settings.notificationDetails) {
                        Text(L10n.showDetails)
                        Text(L10n.showDetailsHint)
                    }
                }
                Toggle(L10n.openAtLogin, isOn: $launchAtLogin)
                Picker(L10n.language, selection: $settings.language) {
                    Text(L10n.languageSystem).tag(LanguagePreference.system)
                    // Language names stay in their own language, so anyone can find theirs.
                    Text(verbatim: "English").tag(LanguagePreference.english)
                    Text(verbatim: "Türkçe").tag(LanguagePreference.turkish)
                }
            }

            Section(L10n.refreshSection) {
                Picker(L10n.checkEvery, selection: $settings.refreshMinutes) {
                    ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                        Text(L10n.minutesShort(n: minutes)).tag(minutes)
                    }
                }
            }

            AutomationSection()
        }
        .formStyle(.grouped)
        .task { await notifier.refreshStatus() }
        .onChange(of: settings.refreshMinutes) { store.start() }
        .onChange(of: settings.notificationsEnabled) { _, enabled in
            if enabled { notifier.requestAuthorization() } else { notifier.removeDelivered() }
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

// MARK: - Bitbucket

private struct BitbucketSettings: View {
    private enum Status: Equatable {
        case connecting
        case connected(String)
        case failed(String)
    }

    @Environment(PRStore.self) private var store
    /// Drafts: nothing is saved or sent anywhere until Save & Connect.
    @State private var serverDraft = ""
    @State private var tokenDraft = ""
    @State private var status: Status?
    @State private var confirmingSignOut = false

    /// The saved token can be reused only when the draft is the same server.
    private var canReuseSavedToken: Bool {
        guard let draft = try? ServerAddress(parsing: serverDraft) else { return false }
        return draft == store.settings.server && store.settings.hasToken(for: draft)
    }

    var body: some View {
        @Bindable var settings = store.settings

        Form {
            Section {
                TextField(L10n.serverURL, text: $serverDraft, prompt: Text(verbatim: "https://bitbucket.example.com"))
                SecureField(L10n.accessToken, text: $tokenDraft,
                            prompt: Text(canReuseSavedToken ? L10n.tokenSavedPlaceholder : L10n.tokenRequiredPlaceholder))
                HStack {
                    switch status {
                    case .connecting:
                        ProgressView().controlSize(.small)
                    case .connected(let name):
                        Text(L10n.connectedAs(name: name)).font(.caption).foregroundStyle(.green)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                    Spacer()
                    if store.isConfigured {
                        Button(L10n.signOut, role: .destructive) { confirmingSignOut = true }
                    }
                    Button(L10n.saveAndConnect, action: saveAndConnect)
                        .keyboardShortcut(.defaultAction)
                        .disabled(status == .connecting || serverDraft.isEmpty
                                  || (tokenDraft.isEmpty && !canReuseSavedToken))
                }
            } header: {
                Text(verbatim: "Bitbucket Server")
            } footer: {
                Text(L10n.tokenHintMac)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L10n.hideDrafts, isOn: $settings.hideDrafts)
                TextField(L10n.onlyTheseRepos, text: $settings.repoFilter, prompt: Text(L10n.filterAllPlaceholder))
            } header: {
                Text(L10n.filters)
            } footer: {
                Text(L10n.filterHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { serverDraft = store.settings.savedServerURL }
        .onDisappear { tokenDraft = "" }
        .confirmationDialog(L10n.signOutConfirmTitle, isPresented: $confirmingSignOut) {
            Button(L10n.signOut, role: .destructive, action: signOut)
        } message: {
            Text(L10n.signOutConfirmMessageMac)
        }
    }

    private func saveAndConnect() {
        status = .connecting
        Task {
            do {
                let name = try await store.connect(serverURL: serverDraft, token: tokenDraft)
                tokenDraft = ""
                serverDraft = store.settings.savedServerURL
                status = .connected(name)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func signOut() {
        do {
            try store.signOut()
            tokenDraft = ""
            status = nil
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.version, value: Self.appVersion)
                LabeledContent {
                    Button(L10n.checkForUpdates) { Updater.shared.checkForUpdates() }
                } label: {
                    Text(L10n.updates)
                    if let last = Updater.shared.lastCheckDate {
                        Text(L10n.lastChecked(time: last.relativeText))
                    } else {
                        Text(L10n.checkedWeekly)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? version
        return build == version ? version : "\(version) (\(build))"
    }
}
