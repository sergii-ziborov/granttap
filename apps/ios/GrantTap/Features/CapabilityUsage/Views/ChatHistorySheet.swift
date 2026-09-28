import SwiftUI

struct ChatHistorySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var agent = "all"
    /// History opens the same chat-first task screen as Active.
    @State private var openedSession: HistoryOpenSession?

    init(
        search: String = "",
        agent: String = "all",
        openedSession: HistoryOpenSession? = nil
    ) {
        _search = State(initialValue: search)
        _agent = State(initialValue: agent)
        _openedSession = State(initialValue: openedSession)
    }

    private var sessions: [SessionInfo] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.allSessionHistory.filter { session in
            agent == "all" || normalizedAgent(session.agent) == agent
        }.filter { session in
            query.isEmpty || [session.displayTitle, session.summary ?? "", session.cwd ?? "",
                              session.branch ?? ""].contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Picker(L("Agent"), selection: $agent) {
                        Text(L("All")).tag("all")
                        ForEach(AgentIdentity.knownIds, id: \.self) { id in
                            Text(AgentIdentity.shortName(id)).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField(L("Search chat history"), text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if sessions.isEmpty {
                    CompatEmptyState(
                        title: "No chat history",
                        systemImage: "clock.arrow.circlepath",
                        description: "The Mac helper reports up to 90 days of local Codex and Claude Code chats."
                    )
                } else {
                    ForEach(SessionProjectGrouping.groups(from: sessions)) { group in
                        Section(group.title) {
                            ForEach(group.sessions) { session in
                                Button { open(session) } label: {
                                    HistoryRow(
                                        session: session,
                                        archived: model.isArchived(session.sessionId),
                                        route: model.chatComputerRoute(forSessionId: session.sessionId)
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button { toggleArchived(session) } label: {
                                        Label(model.isArchived(session.sessionId) ? "Restore" : "Archive",
                                              systemImage: model.isArchived(session.sessionId)
                                              ? "arrow.uturn.backward" : "archivebox")
                                    }
                                    .tint(model.isArchived(session.sessionId) ? Theme.ok : Theme.claude)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Chat history"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
            .background(
                NavigationLink(destination: historyDestination,
                               isActive: historyNavigationActive) { EmptyView() }
                    .hidden()
            )
        }
    }

    private var historyNavigationActive: Binding<Bool> {
        Binding(
            get: { openedSession != nil },
            set: { if !$0 { openedSession = nil } }
        )
    }

    @ViewBuilder
    private var historyDestination: some View {
        if let item = openedSession,
           let session = model.sessionHistory.first(where: { $0.sessionId == item.id })
            ?? model.archivedSessions[item.id]
            ?? model.sessions.first(where: { $0.sessionId == item.id })
            ?? sessions.first(where: { $0.sessionId == item.id }) {
            TaskChatView(session: session).environmentObject(model)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    private func normalizedAgent(_ value: String) -> String {
        AgentIdentity.normalize(value)
    }

    func open(_ session: SessionInfo) {
        if openedSession?.id != session.sessionId {
            openedSession = HistoryOpenSession(id: session.sessionId)
        }
    }

    func toggleArchived(_ session: SessionInfo, using target: AppModel? = nil) {
        let target = target ?? model
        target.setSessionArchived(session.sessionId, !target.isArchived(session.sessionId))
    }
}
