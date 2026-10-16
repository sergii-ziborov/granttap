import SwiftUI

/// A separate View keeps rich row construction inside List's visible cells.
/// Shared Task settings are resolved once by the parent, not once per saved row.
struct TaskChatTimelineRow: View {
    let row: ChatTimelineRow
    let accent: Color
    let servers: [McpServerInfo]
    let focusEntryId: String?
    let highlightedEntryId: String?
    let replyChanges: [String: [RecordedFileChange]]
    let currentReplyFinalId: String?

    @ViewBuilder
    var body: some View {
        switch row {
        case .item(.activity(let entry)):
            let changes = entry.kind == "final" ? replyChanges[entry.id] ?? [] : []
            VStack(alignment: .leading, spacing: 10) {
                ActivityRow(entry: entry, accent: accent, compact: false,
                        server: server(for: entry))
                // Scrolling to the entry is not enough on a dense
                // transcript: say which one it was.
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(highlightedEntryId == entry.id ? accent.opacity(0.18) : .clear)
                )
                if !changes.isEmpty, entry.id != currentReplyFinalId {
                    ChatFileChangesCard(files: changes, complete: entry.fileChangesComplete != false)
                        .padding(.horizontal, 6)
                }
            }
            .id(ChatScrollTarget.forEntry(entry))
        case .item(.mesh(let event)):
            ProjectMeshTimelineRow(event: event)
        case .run(let run):
            // A run holding the entry someone tapped in history opens itself,
            // or the tap lands on a summary of what it named.
            ActivityRunRow(
                run: run, accent: accent,
                forceOpen: run.entries.contains {
                    $0.id == focusEntryId || $0.id == highlightedEntryId
                },
                highlightedEntryId: highlightedEntryId,
                serverFor: { server(for: $0) }
            )
            // The same inset as every other row: a run that sat six points
            // further left made everything after it look indented.
            .padding(.horizontal, 6)
            .id(run.id)
        }
    }

    private func server(for entry: ActivityEntry) -> McpServerInfo? {
        entry.mcpServer.flatMap { name in
            servers.first { $0.name == name }
        }
    }
}
