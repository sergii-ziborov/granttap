import SwiftUI

struct ChatAgentConversationsSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let entries: [ActivityEntry]
    let threads: [ChildThreadDisplayRow]
    let requestId: String?
    let executionIds: [String]
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var currentWork: ChatRequestWork {
        let ids = executionIds.isEmpty ? [model.resolvedSessionId(session.sessionId)] : executionIds
        let loaded = ids.flatMap { model.activities[$0]?.entries ?? [] }
        let allEntries = loaded.isEmpty ? entries : loaded.sorted { $0.createdAt < $1.createdAt }
        let rows = ids.flatMap { id in
            ChildThreadTree.rows(rootId: id, threads: model.knownSession(for: id, preferredAgent: nil)?.childThreads
                ?? threads.filter { $0.executionSessionId == id }.map(\.thread),
                activity: model.activities[id]?.entries ?? entries)
        }
        return ChatRequestWork(requestId: requestId, entries: allEntries, threads: rows)
    }

    var body: some View {
        let work = currentWork
        ChatSheetNavigation(title: L("Agents"), doneIdentifier: "chat.agents.done",
            onClose: { if let onClose { onClose() } else { dismiss() } }) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if work.threads.isEmpty {
                        Text(L("No agents were reported for this request."))
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    ForEach(work.threads) { row in
                        let owner = model.knownSession(for: row.executionSessionId ?? session.sessionId,
                                                       preferredAgent: nil) ?? session
                        AgentThreadTranscript(
                            row: row,
                            entries: work.entries.filter { $0.childThreadId == row.thread.threadId },
                            accent: Theme.accent(for: owner.agent),
                            servers: owner.mcpServers ?? []
                        ) {
                            model.requestThreadEvents(row.executionSessionId ?? session.sessionId,
                                                      threadId: row.thread.threadId)
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
