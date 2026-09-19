import SwiftUI

/// One row of a chat's timeline: an activity, an approval, a question, or a
/// message, in the shape the list expects.
extension TaskChatView {
    /// One transcript row. Extracted because the list body became an
    /// expression the type-checker refused to finish.
    @ViewBuilder
    func timelineRow(_ row: ChatTimelineRow) -> some View {
        rowBody(row)
            .id(row.id)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChatRowFrameKey.self,
                        value: [row.id: geo.frame(in: .named("chat-scroll"))]
                    )
                }
            )
    }

    @ViewBuilder
    func rowBody(_ row: ChatTimelineRow) -> some View {
        switch row {
        case .item(.activity(let entry)):
            ActivityRow(entry: entry, accent: accent, compact: false,
                        server: server(for: entry))
                // Scrolling to the entry is not enough on a dense
                // transcript: say which one it was.
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(highlightedEntryId == entry.id ? accent.opacity(0.18) : .clear)
                )
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
        }
    }

    func server(for entry: ActivityEntry) -> McpServerInfo? {
        entry.mcpServer.flatMap { name in
            currentSession.mcpServers?.first { $0.name == name }
        }
    }
}
