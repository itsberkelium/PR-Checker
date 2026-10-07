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
                            Button("Open Notification Settings…") { notifier.openSystemSettings() }
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
        }
        .formStyle(.grouped)
        .task { await notifier.refreshStatus() }
        .onChange(of: settings.refreshMinutes) { store.start() }
        .onChange(of: settings.notificationsEnabled) { _, enabled in
            if enabled { notifier.requestAuthorization() }
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
    @Environment(PRStore.self) private var store
    @State private var token = ""
    @State private var testResult: String?

    var body: some View {
        @Bindable var settings = store.settings

        Form {
            Section {
                TextField("Server URL", text: $settings.serverURL, prompt: Text("https://bitbucket.example.com"))
                SecureField("Access token", text: $token)
                HStack {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(store.errorMessage == nil ? Color.green : Color.red)
                    }
                    Spacer()
                    Button("Save & Connect", action: saveAndConnect)
                        .keyboardShortcut(.defaultAction)
                        .disabled(token.isEmpty || settings.serverURL.isEmpty)
                }
            } header: {
                Text("Bitbucket Server")
            } footer: {
                Text("Create a token under Profile → Manage account → HTTP access tokens with Read permission. It is stored in your Keychain.")
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
        .onAppear { token = store.settings.token }
    }

    private func saveAndConnect() {
        store.settings.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
        testResult = nil
        Task {
            await store.refresh()
            if let error = store.errorMessage {
                testResult = error
            } else {
                testResult = "Connected as \(store.username ?? "unknown")"
                store.start()
            }
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
                    Button("Check for Updates…") { Updater.shared.checkForUpdates() }
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
