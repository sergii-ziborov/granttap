import DesktopInspectorCore
import SwiftUI

struct TaskConversationView: View {
    let activity: TaskActivitySnapshot?
    let loading: Bool
    let retry: () -> Void

    var body: some View {
        if let activity, !activity.entries.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(activity.entries) { entry in
                        switch entry.kind {
                        case "user": personRow(entry)
                        case "message", "final": agentRow(entry)
                        default: activityRow(entry)
                        }
                    }
                    if activity.truncated {
                        Text("Showing the latest conversation entries from this Mac")
                            .font(.caption).foregroundStyle(DesktopTheme.muted)
                    }
                }
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("task.conversation")
        } else if let activity {
            VStack(spacing: 12) {
                ContentUnavailableView("No conversation recorded",
                                       systemImage: "bubble.left.and.bubble.right",
                                       description: Text(activity.session_id == nil
                                                         ? "This Task has no linked native session on this Mac."
                                                         : "The linked native session has no readable entries yet."))
                Button("Refresh conversation") { retry() }
            }
        } else if loading {
            ProgressView("Loading conversation…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                ContentUnavailableView("Conversation unavailable",
                                       systemImage: "bubble.left.and.bubble.right",
                                       description: Text("No native conversation was found for this Task on this Mac."))
                Button("Retry conversation") { retry() }
            }
        }
    }

    private func personRow(_ entry: TaskActivitySnapshot.Entry) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 48)
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(DesktopTheme.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(DesktopTheme.raised,
                            in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(DesktopTheme.line))
        }
    }

    private func agentRow(_ entry: TaskActivitySnapshot.Entry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: entry.kind == "final" ? "checkmark.circle" : "text.bubble")
                .font(.system(size: 13))
                .foregroundStyle(DesktopTheme.muted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.kind == "final" ? "FINAL" : "AGENT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(DesktopTheme.muted)
                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundStyle(DesktopTheme.ink)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private func activityRow(_ entry: TaskActivitySnapshot.Entry) -> some View {
        DisclosureGroup {
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(DesktopTheme.muted)
                .textSelection(.enabled)
                .padding(.top, 6)
        } label: {
            Label(entry.summary ?? entry.tool_name ?? "Activity",
                  systemImage: entry.kind == "status" ? "info.circle" : "terminal")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesktopTheme.muted)
                .lineLimit(1)
        }
        .padding(.leading, 29)
    }
}
