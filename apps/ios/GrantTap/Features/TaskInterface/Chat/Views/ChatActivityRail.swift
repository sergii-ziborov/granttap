import SwiftUI

/// Current reply changes and nested execution conversations stay beside the composer.
struct ChatActivityRail: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let entries: [ActivityEntry]
    let threads: [ChildThreadDisplayRow]
    @State private var sheet: Destination?

    private enum Destination: String, Identifiable {
        case files, agents
        var id: String { rawValue }
    }
    private var files: [RecordedFileChange] {
        ChatFileChanges.currentReply(entries: entries.filter { $0.childThreadId == nil })
    }
    private var hasWorkspace: Bool {
        session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        if hasWorkspace || !files.isEmpty || !threads.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if hasWorkspace || !files.isEmpty {
                        Button { sheet = .files } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text(files.isEmpty ? L("Files")
                                     : LPlural(files.count, one: "%d file", many: "%d files"))
                                if !files.isEmpty {
                                    Text("+\(files.reduce(0) { $0 + $1.linesAdded })")
                                        .foregroundStyle(Theme.ok)
                                    Text("−\(files.reduce(0) { $0 + $1.linesRemoved })")
                                        .foregroundStyle(Theme.riskHigh)
                                }
                            }
                        }
                        .buttonStyle(ChatActivityPill())
                        .accessibilityIdentifier("chat.work.files")
                    }
                    if !threads.isEmpty {
                        Button { sheet = .agents } label: {
                            Label(LPlural(threads.count, one: "%d agent", many: "%d agents"),
                                  systemImage: "person.2")
                        }
                        .buttonStyle(ChatActivityPill())
                        .accessibilityIdentifier("chat.work.agents")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            .accessibilityIdentifier("chat.work.summary")
            .sheet(item: $sheet) { destination in
                switch destination {
                case .files:
                    ChatWorkFilesSheet(model: model, session: session, files: files)
                        .id(session.sessionId)
                case .agents:
                    ChatAgentConversationsSheet(model: model, session: session,
                                                entries: entries, threads: threads)
                }
            }
        }
    }
}

private struct ChatActivityPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .pointerFeedback(cornerRadius: 18, isPressed: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .frame(minHeight: 44)
    }
}
