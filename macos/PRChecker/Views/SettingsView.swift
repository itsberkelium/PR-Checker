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
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            BitbucketSettings()
                .tabItem { Label("Bitbucket", systemImage: "server.rack") }
                .tag(Tab.bitbucket)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
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
            Section("General") {
                Toggle("Notifications", isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled {
                    if notifier.isBlockedBySystem {
                        LabeledContent {
                            Button("Open Notification Settings") { notifier.openSystemSettings() }
                        } label: {
                            Label {
                                Text("Turned off in System Settings")
                                Text("macOS is blocking PR Checker's notifications. Turn on Allow Notifications.")
                            } icon: {
                                Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                            }
                        }
                    } else {
                        LabeledContent("Check delivery") {
                            Button("Send Test Notification") { notifier.sendTest() }
                        }
                    }
                    Toggle(isOn: $settings.notificationDetails) {
                        Text("Show pull request details")
                        Text("Off: notifications don't show titles, names or results, e.g. while screen sharing.")
                    }
                }
                Toggle("Open at login", isOn: $launchAtLogin)
            }

            Section("Refresh") {
                Picker("Check every", selection: $settings.refreshMinutes) {
                    ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
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
                TextField("Server URL", text: $serverDraft, prompt: Text("https://bitbucket.example.com"))
                SecureField("Access token", text: $tokenDraft,
                            prompt: Text(canReuseSavedToken ? "Saved – leave empty to keep" : "Required"))
                HStack {
                    switch status {
                    case .connecting:
                        ProgressView().controlSize(.small)
                    case .connected(let name):
                        Text("Connected as \(name)").font(.caption).foregroundStyle(.green)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                    Spacer()
                    if store.isConfigured {
                        Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    }
                    Button("Save & Connect", action: saveAndConnect)
                        .keyboardShortcut(.defaultAction)
                        .disabled(status == .connecting || serverDraft.isEmpty
                                  || (tokenDraft.isEmpty && !canReuseSavedToken))
                }
            } header: {
                Text("Bitbucket Server")
            } footer: {
                Text("Create a token under Profile → Manage account → HTTP access tokens with Read permission. It is stored in your Keychain and only sent to this server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hide draft pull requests", isOn: $settings.hideDrafts)
                TextField("Only these projects/repos", text: $settings.repoFilter, prompt: Text("All"))
            } header: {
                Text("Filters")
            } footer: {
                Text("Comma-separated project keys or PROJECT/repo-slug, e.g. PROJ, OTHER/my-repo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { serverDraft = store.settings.savedServerURL }
        .onDisappear { tokenDraft = "" }
        .confirmationDialog("Sign out of Bitbucket?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive, action: signOut)
        } message: {
            Text("Removes the access token from your Keychain and the pull request data PR Checker stored for this server.")
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
                LabeledContent("Version", value: Self.appVersion)
                LabeledContent {
                    Button("Check for Updates") { Updater.shared.checkForUpdates() }
                } label: {
                    Text("Updates")
                    if let last = Updater.shared.lastCheckDate {
                        Text("Last checked \(last, format: .relative(presentation: .named))")
                    } else {
                        Text("Checked automatically once a week")
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
