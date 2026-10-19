import SwiftUI

struct ChatAgentConversationsSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let entries: [ActivityEntry]
    let threads: [ChildThreadDisplayRow]
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var latestEntries: [ActivityEntry] {
        model.activities[model.resolvedSessionId(session.sessionId)]?.entries ?? entries
    }
    private var currentRows: [ChildThreadDisplayRow] {
        ChildThreadTree.rows(rootId: model.resolvedSessionId(session.sessionId),
            threads: model.knownSession(for: session.sessionId, preferredAgent: session.agent)?.childThreads
                ?? threads.map(\.thread), activity: latestEntries)
    }

    var body: some View {
        ChatSheetNavigation(title: L("Agents"), doneIdentifier: "chat.agents.done",
            onClose: { if let onClose { onClose() } else { dismiss() } }) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if currentRows.isEmpty {
                        Text(L("No agents have been reported for this Task yet."))
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    ForEach(currentRows) { row in
                        AgentThreadTranscript(
                            row: row,
                            entries: latestEntries.filter { $0.childThreadId == row.thread.threadId },
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
            .onAppear {
                model.relayForSession(session.sessionId)?.requestSessionsRefresh()
            }
        }
    }
}
