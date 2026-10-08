import SwiftUI

/// Settings → General → Automation: on/off, a one-line command preview and the last run.
/// The command itself is edited in a separate sheet to keep this compact.
struct AutomationSection: View {
    @Environment(PRStore.self) private var store
    private let monitor = AutomationMonitor.shared
    @State private var editing = false
    @State private var askingForBacklog = false
    @State private var confirmingRunNow = false

    private var settings: AppSettings { store.settings }
    private var hasCommand: Bool { !settings.automationCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        @Bindable var settings = store.settings

        Section("Automation") {
            Toggle(isOn: $settings.automationEnabled) {
                Text("Run a command for new review requests")
                Text("Once per commit for pull requests in To review, e.g. to start an automated pre-check.")
            }

            if settings.automationEnabled {
                LabeledContent {
                    Button(hasCommand ? "Edit" : "Set Command") { editing = true }
                } label: {
                    Text("Command")
                    Text(hasCommand ? settings.automationCommand : "Not set")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent {
                    HStack {
                        Button("Run Now") { confirmingRunNow = true }
                            .disabled(!hasCommand || store.toReview.isEmpty)
                        Button("Show Log") { NSWorkspace.shared.open(Automation.logFile) }
                            .disabled(!FileManager.default.fileExists(atPath: Automation.logFile.path))
                    }
                } label: {
                    Text("Last run")
                    Text(lastRunText).font(.caption)
                }
            }
        }
        .sheet(isPresented: $editing) {
            AutomationCommandEditor(command: settings.automationCommand, previewItem: store.toReview.first) { saved in
                settings.automationCommand = saved
            }
        }
        .onChange(of: settings.automationEnabled) { _, enabled in
            guard enabled else { return }
            if !hasCommand {
                editing = true
            } else if !store.automationBacklog.isEmpty {
                askingForBacklog = true
            }
        }
        .confirmationDialog(backlogQuestion, isPresented: $askingForBacklog, titleVisibility: .visible) {
            Button("Run for \(store.automationBacklog.count) Pull Requests") { store.runAutomationNow() }
            Button("Only New Ones From Now") { store.skipAutomationBacklog() }
            Button("Cancel", role: .cancel) { settings.automationEnabled = false }
        } message: {
            Text("They're already in your review list. The command may post comments on them.")
        }
        .confirmationDialog("Run the command for \(store.toReview.count) pull requests now?",
                            isPresented: $confirmingRunNow, titleVisibility: .visible) {
            Button("Run Now") { store.runAutomationNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every pull request in To review, including commits it already ran for.")
        }
    }

    private var backlogQuestion: String {
        let count = store.automationBacklog.count
        return "Run the command for the \(count) pull request\(count == 1 ? "" : "s") waiting now?"
    }

    private var lastRunText: String {
        if monitor.running > 0 { return "Running for \(monitor.running) pull request\(monitor.running == 1 ? "" : "s")…" }
        guard let last = monitor.last else { return "Not run since PR Checker started" }
        let when = last.started.formatted(.relative(presentation: .named))
        if let error = last.startError { return "\(last.pullRequest) · \(when) · couldn't start: \(error)" }
        let outcome = switch last.exitCode {
        case nil: "running"
        case 0: "finished"
        case let code?: "failed (exit \(code))"
        }
        return "\(last.pullRequest) · \(when) · \(outcome)"
    }
}

/// Edits the automation command with placeholder buttons and a live preview of the
/// exact arguments the command would receive.
struct AutomationCommandEditor: View {
    let previewItem: PRItem?
    let onSave: (String) -> Void
    private let original: String
    @State private var command: String
    @Environment(\.dismiss) private var dismiss

    init(command: String, previewItem: PRItem?, onSave: @escaping (String) -> Void) {
        original = command
        _command = State(initialValue: command)
        self.previewItem = previewItem
        self.onSave = onSave
    }

    private var trimmed: String { command.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var preview: Result<[String], Error>? {
        guard !trimmed.isEmpty else { return nil }
        return Result { try Automation.arguments(for: trimmed, item: previewItem ?? Automation.sample) }
    }

    private var canSave: Bool {
        trimmed != original.trimmingCharacters(in: .whitespacesAndNewlines)
            && (trimmed.isEmpty || (try? preview?.get()) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Automation Command").font(.headline)
            Text("Runs once per commit for pull requests in To review. Placeholders are filled into each argument; nothing goes through a shell.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CommandTextView(text: $command)
                .frame(height: 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))

            HStack(spacing: 6) {
                Text("Insert").font(.caption).foregroundStyle(.secondary)
                ForEach(Automation.placeholders, id: \.self) { name in
                    Button("{\(name)}") { insert("{\(name)}") }
                        .font(.caption.monospaced())
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            previewView

            HStack {
                Button("Clear", role: .destructive) { command = "" }
                    .disabled(command.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    @ViewBuilder
    private var previewView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(previewItem.map { "Arguments for \($0.id)" } ?? "Arguments for an example pull request")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch preview {
            case nil:
                Text("Enter a command, e.g. /usr/bin/python3 ~/bin/check.py --pr {link} --commit {commit}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .success(let arguments):
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(arguments.enumerated()), id: \.offset) { index, argument in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index)").foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                                Text(argument).textSelection(.enabled)
                            }
                        }
                    }
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
    }

    private func insert(_ placeholder: String) {
        if !command.isEmpty && !command.hasSuffix(" ") { command += " " }
        command += placeholder
    }
}

/// A monospaced text view that wraps long commands only at spaces, so an argument like
/// `--commit` or a long path is never split across lines (the standard text view also
/// breaks after hyphens, which looks like a line break inside the command).
private struct CommandTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.layoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// Break lines only right after whitespace.
        func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
            guard charIndex > 0, let storage = layoutManager.textStorage else { return true }
            let previous = (storage.string as NSString).character(at: charIndex - 1)
            return CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(previous) ?? " ")
        }
    }
}
