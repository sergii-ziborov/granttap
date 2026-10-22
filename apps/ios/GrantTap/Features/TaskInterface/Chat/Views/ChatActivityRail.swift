import SwiftUI

/// Floating access to recorded work, workspace files and nested conversations.
struct ChatActivityRail: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let entries: [ActivityEntry]
    let threads: [ChildThreadDisplayRow]
    var recordedFiles: [RecordedFileChange]? = nil
    var requestId: String? = nil
    var executionIds: [String] = []
    @State private var sheet: Destination?

    private enum Destination: String, Identifiable {
        case files, agents
        var id: String { rawValue }
    }
    private var files: [RecordedFileChange] {
        recordedFiles ?? ChatFileChanges.currentReply(entries: entries.filter { $0.childThreadId == nil })
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChatMessageQueueBar(session: session).environmentObject(model)
                Button { sheet = .files } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text(files.isEmpty ? L("Files")
                             : LPlural(files.count, one: "%d file", many: "%d files"))
                        if !files.isEmpty {
                            Text("+\(files.reduce(0) { $0 + $1.linesAdded })").foregroundStyle(Theme.ok)
                            Text("−\(files.reduce(0) { $0 + $1.linesRemoved })").foregroundStyle(Theme.riskHigh)
                        }
                    }
                }
                .buttonStyle(ChatAccessoryPillStyle())
                .accessibilityIdentifier("chat.work.files")
                Button { sheet = .agents } label: {
                    HStack(spacing: 6) {
                        ChatAgentGlyph()
                        Text(threads.isEmpty ? L("Agents")
                             : LPlural(threads.count, one: "%d agent", many: "%d agents"))
                    }
                }
                .buttonStyle(ChatAccessoryPillStyle())
                .accessibilityIdentifier("chat.work.agents")
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .accessibilityIdentifier("chat.work.summary")
        .sheet(item: $sheet) { destination in
            switch destination {
            case .files:
                ChatWorkFilesSheet(model: model, session: session, files: files,
                                   onClose: { sheet = nil }).id(session.sessionId)
            case .agents:
                ChatAgentConversationsSheet(model: model, session: session, entries: entries,
                                            threads: threads, requestId: requestId, executionIds: executionIds,
                                            onClose: { sheet = nil })
            }
        }
    }
}
