import SwiftUI

struct PRRow: View {
    let item: PRItem
    let showsAuthor: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(item.url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text(item.updated, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                badges
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.primary.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.url.absoluteString)
    }

    private var subtitle: String {
        let who = showsAuthor ? "\(item.authorName) · " : ""
        return "\(item.repoName) #\(item.number) · \(who)\(item.sourceBranch) → \(item.targetBranch)"
    }

    private var badges: some View {
        HStack(spacing: 10) {
            if item.isDraft {
                Badge("Draft", systemImage: "pencil.circle", color: .secondary)
            }
            if item.hasNewCommits {
                Badge("New commits", systemImage: "arrow.up.circle", color: .blue)
            }
            if !item.reviewers.isEmpty {
                Badge("\(item.approvals)/\(item.reviewers.count)", systemImage: "checkmark.circle",
                      color: item.approvals > 0 ? .green : .secondary)
                    .help(item.reviewers.map { "\($0.name): \($0.status.label)" }.joined(separator: "\n"))
            }
            if item.needsWork {
                Badge("Needs work", systemImage: "hand.raised", color: .orange)
            }
            if item.hasConflicts {
                Badge("Conflicts", systemImage: "exclamationmark.triangle", color: .red)
            }
            switch item.build {
            case .passed: Badge("Build", systemImage: "checkmark.seal", color: .green)
            case .failed: Badge("Build", systemImage: "xmark.seal", color: .red)
            case .running: Badge("Build", systemImage: "clock", color: .secondary)
            case .none: EmptyView()
            }
            if item.commentCount > 0 {
                Badge("\(item.commentCount)", systemImage: "bubble.left", color: .secondary)
            }
            if item.openTaskCount > 0 {
                Badge("\(item.openTaskCount)", systemImage: "checklist", color: .orange)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let systemImage: String
    let color: Color

    init(_ text: String, systemImage: String, color: Color) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }
}

extension ReviewStatus {
    var label: String {
        switch self {
        case .approved: "Approved"
        case .unapproved: "Not reviewed"
        case .needsWork: "Needs work"
        }
    }
}
