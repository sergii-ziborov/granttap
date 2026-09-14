import SwiftUI

/// What the two figures about the present moment stand for: what is still
/// waiting for a person, and which computers were awake to be counted.
struct UsageWaitingView: View {
    @ObservedObject private var model = AppModel.shared

    /// One waiting thing, whichever of the three kinds it came from.
    private struct Waiting: Identifiable {
        let id: String
        let eyebrow: String
        let title: String
        let detail: String?
        let sessionId: String?
    }

    private var waiting: [Waiting] {
        model.pending.map { request in
            Waiting(id: "approval\u{1f}\(request.requestId)", eyebrow: L("Approval"),
                    title: request.title, detail: request.command ?? request.tool,
                    sessionId: request.sessionId)
        } + model.questions.map { question in
            Waiting(id: "question\u{1f}\(question.requestId ?? "\(question.createdAt)")",
                    eyebrow: L("Question"), title: question.text, detail: nil,
                    sessionId: question.sessionId)
        } + model.meshNeedsYouEvents.map { event in
            let item = model.meshAttentionItem(event)
            return Waiting(id: "mesh\u{1f}\(event.eventId)", eyebrow: L("Project"),
                           title: item.title, detail: item.detail, sessionId: item.sessionId)
        }
    }

    var body: some View {
        List {
            if waiting.isEmpty {
                CompatEmptyState(title: "Nothing is waiting for you", systemImage: "checkmark.circle")
            } else {
                ForEach(waiting) { item in
                    if let session = session(for: item.sessionId) {
                        NavigationLink {
                            TaskChatView(session: session).environmentObject(model)
                        } label: {
                            row(item)
                        }
                    } else {
                        row(item)
                    }
                }
            }
        }
        .navigationTitle(L("Waiting for you"))
    }

    private func session(for sessionId: String?) -> SessionInfo? {
        guard let sessionId else { return nil }
        let resolved = model.resolvedSessionId(sessionId)
        return model.sessions.first { $0.sessionId == resolved }
    }

    private func row(_ item: Waiting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.eyebrow.uppercased())
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.muted)
            Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
            if let detail = item.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The computers the figure counted, and the agents each is carrying.
struct UsageComputersView: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        List {
            if model.connectionRegistry.connections.isEmpty {
                CompatEmptyState(title: "No computers are linked", systemImage: "desktopcomputer")
            } else {
                ForEach(model.connectionRegistry.connections, id: \.id) { connection in
                    Section {
                        let snapshot = model.snapshotForConnection(connection)
                        CompatLabeledContent(L("Status")) {
                            HStack(spacing: 6) {
                                Circle().fill(snapshot.statusColor).frame(width: 8, height: 8)
                                Text(snapshot.statusTitle).foregroundStyle(Theme.muted)
                            }
                        }
                        // Each agent opens the same live screen the connection
                        // pill leads to, so a number here and a number there
                        // are the same number.
                        let agents = model.machineLoadByRoom[connection.id]?.agents ?? []
                        if agents.isEmpty {
                            Text(L("This computer has not reported an agent running."))
                                .font(.caption).foregroundStyle(Theme.muted)
                        } else {
                            ForEach(agents, id: \.agent) { sample in
                                NavigationLink {
                                    AgentLoadDetailView(room: connection.id, agent: sample.agent)
                                        .environmentObject(model)
                                } label: {
                                    CompatLabeledContent(
                                        AgentIdentity.displayName(sample.agent),
                                        value: ConnectionLoadFormat.cpu(sample.cpuPercent)
                                    )
                                }
                            }
                        }
                    } header: {
                        Text(connection.displayName)
                    }
                }
            }
        }
        .navigationTitle(L("Active computers"))
    }
}
