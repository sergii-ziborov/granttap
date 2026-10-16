import SwiftUI

struct ChatAgentConversationsSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let entries: [ActivityEntry]
    let threads: [ChildThreadDisplayRow]
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ChatSheetNavigation(title: L("Agent conversations"), doneIdentifier: "chat.agents.done",
            onClose: { if let onClose { onClose() } else { dismiss() } }) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(L("Agent conversations are nested executions of this Task."))
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    ForEach(threads) { row in
                        AgentThreadTranscript(
                            row: row,
                            entries: entries.filter { $0.childThreadId == row.thread.threadId },
                            accent: Theme.accent(for: session.agent),
                            servers: session.mcpServers ?? []
                        ) {
                            model.requestThreadEvents(session.sessionId, threadId: row.thread.threadId)
                        }
                        .padding(.leading, TaskChatView.threadIndent(row.visualDepth))
                        .accessibilityIdentifier("chat.agents.conversation.\(row.thread.threadId)")
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
        }
    }
}
