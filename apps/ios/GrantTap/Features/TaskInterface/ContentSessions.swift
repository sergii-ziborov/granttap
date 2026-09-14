import SwiftUI

enum AgentHealth: Int, Comparable {
    case needsYou = 0
    case blocked = 1
    case toolFailure = 2
    case highContext = 3
    case possiblyStalled = 4
    case offline = 5
    case working = 6
    case idle = 7
    case finished = 8

    static func < (lhs: AgentHealth, rhs: AgentHealth) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension ContentView {
    var emptySessionsHint: String {
        switch model.connectionSnapshot.phase {
        case .notLinked: return L("Connect a computer to see its coding-agent tasks here.")
        case .phoneOffline, .macOffline: return L("A linked computer is offline. Open connection status to repair it.")
        case .needRepair: return L("This connection needs repair before tasks can update.")
        case .live, .demo: return L("Start a new task, or pull to refresh.")
        }
    }

    var nowSessionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            nowGroup("At Risk", tasks: atRiskTasks)
            nowGroup("Working", tasks: activeNowTasks)
            nowGroup("Blocked", tasks: blockedTasks)
            nowGroup("Recently Finished", tasks: recentTasks)
            if activeTaskItems.isEmpty {
                Text(emptySessionsHint)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder func nowGroup(_ title: String, tasks: [TaskListItem]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: title)
                ForEach(tasks) { item in
                    Button { open(item) } label: {
                        TaskListCard(item: item, route: ownerRoute(item))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField(L("Search tasks"), text: $sessionSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))

            Picker(L("Tasks"), selection: $showArchivedSessions) {
                Text(L("Active")).tag(false)
                Text(L("History")).tag(true)
            }
            .pickerStyle(.segmented)

            if filteredTaskItems.isEmpty {
                CompatEmptyState(
                    title: showArchivedSessions ? L("No history") : L("No active tasks"),
                    systemImage: showArchivedSessions ? "clock.arrow.circlepath" : "tray",
                    description: emptySessionsHint
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(filteredTaskItems) { item in
                    Button { open(item) } label: {
                        TaskListCard(item: item, route: ownerRoute(item))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task.\(item.id)")
                    .contextMenu {
                        if !item.sessionIds.isEmpty {
                            Button(L("Hide")) {
                                item.sessionIds.forEach { model.setSessionArchived($0, true) }
                            }
                        }
                    }
                }
            }

            if !model.archivedSessions.isEmpty {
                NavigationLink {
                    HiddenTasksView().environmentObject(model)
                } label: {
                    HStack {
                        Label(L("Hidden tasks"), systemImage: "eye.slash")
                        Spacer()
                        Text("\(model.archivedSessions.count)")
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(12)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("tasks.hidden")
            }
        }
    }

    var filteredTaskItems: [TaskListItem] {
        let sessions = showArchivedSessions
            ? taskHistorySessions
            : model.sessions.filter { !model.isArchived($0.sessionId) }
        let source = TaskListCatalog.items(
            model: model, sessions: sessions, history: showArchivedSessions
        ).filter { item in
            if !showArchivedSessions && isTaskHidden(item) { return false }
            return showArchivedSessions
                ? item.isTerminal
                : !item.isTerminal && !isIdleOrFinished(item)
        }
        let query = sessionSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return source.filter { item in
            guard !query.isEmpty else { return true }
            return [item.title, item.summary ?? "", item.projectName,
                    item.ownerProvider, item.ownerName]
                .contains { $0.lowercased().contains(query) }
        }
    }

    /// Active work is work something is still running.
    ///
    /// A session that ended without saying so leaves a task behind with its old
    /// name and its last state. Those belong to history: listing them beside
    /// live chats is what made the names on the phone stop matching the agents.
    var activeTaskItems: [TaskListItem] {
        TaskListCatalog.items(
            model: model,
            sessions: model.sessions.filter { !model.isArchived($0.sessionId) }
        ).filter {
            !isTaskHidden($0) && !$0.isTerminal && $0.hasOpenExecution
        }
    }

    var taskHistorySessions: [SessionInfo] {
        let finishedCurrent = model.sessions.filter {
            ["finished", "completed", "failed", "cancelled"].contains($0.state)
        }
        return AppModel.deduplicatedSessions(model.allSessionHistory + finishedCurrent)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func isTaskHidden(_ item: TaskListItem) -> Bool {
        !item.sessionIds.isEmpty && item.sessionIds.allSatisfy(model.isArchived)
    }

    func ownerRoute(_ item: TaskListItem) -> ChatComputerRoute? {
        item.currentSession.flatMap { model.chatComputerRoute(forSessionId: $0.sessionId) }
    }

    func health(for item: TaskListItem) -> AgentHealth {
        let taskSessionIds = Set(item.sessionIds)
        if model.pending.contains(where: { taskSessionIds.contains($0.sessionId ?? "") })
            || model.questions.contains(where: { taskSessionIds.contains($0.sessionId ?? "") })
            || model.meshNeedsYouEvents.contains(where: { $0.taskId == item.taskId }) {
            return .needsYou
        }
        if item.state == "blocked" { return .blocked }
        guard let session = item.currentSession else {
            if item.isTerminal { return .finished }
            // No live session here. Only an execution still open somewhere else
            // justifies calling the task working; a task whose owning session is
            // gone is not running, however it was last recorded.
            return item.state == "working" && item.hasOpenExecution ? .working : .idle
        }
        if session.state == "idle" { return .idle }
        if hasRecentToolFailure(session.sessionId) { return .toolFailure }
        if let used = session.contextTokensUsed, let window = session.contextWindow,
           window > 0, Double(used) / Double(window) >= 0.85 { return .highContext }
        if let route = ownerRoute(item), route.phase != .live { return .offline }
        if session.state == "working", session.idleFor >= 15 * 60 { return .possiblyStalled }
        if session.state == "working" { return .working }
        return ["idle", "waiting"].contains(session.state) ? .idle : .finished
    }

    func isIdleOrFinished(_ item: TaskListItem) -> Bool {
        let value = health(for: item)
        guard value == .idle else { return value == .finished }
        return !item.hasOpenExecution
    }

    func hasRecentToolFailure(_ sessionId: String) -> Bool {
        let recent = model.capabilityUsageEvents(forSessionId: sessionId)
            .filter { $0.effectiveOutcome == .error }
        let counts = Dictionary(grouping: recent, by: { "\($0.kind.rawValue):\($0.name)" })
        return counts.values.contains { $0.count >= 3 }
    }

    func open(_ session: SessionInfo) {
        revealedSessionAction = nil
        if openedSession?.id != session.sessionId {
            openedSession = OpenSession(id: session.sessionId)
        }
    }

    func open(_ item: TaskListItem) {
        revealedSessionAction = nil
        switch item.destination {
        case .task(let route):
            if let session = item.currentSession { open(session) }
            else { openedTaskRoute = route }
        case .session(let sessionId):
            guard let session = item.currentSession, session.sessionId == sessionId else { return }
            open(session)
        }
    }
}

struct HiddenTasksView: View {
    @EnvironmentObject private var model: AppModel

    private var sessions: [SessionInfo] { model.sessionsForArchiveView(true) }

    var body: some View {
        Group {
            if sessions.isEmpty {
                CompatEmptyState(
                    title: L("No hidden tasks."), systemImage: "eye.slash",
                    description: L("Hidden tasks can be restored from here.")
                )
                .padding(16)
            } else {
                List(sessions) { session in
                    VStack(alignment: .leading, spacing: 10) {
                        SessionCard(
                            session: session,
                            route: model.chatComputerRoute(forSessionId: session.sessionId)
                        )
                        Button {
                            model.setSessionArchived(session.sessionId, false)
                        } label: {
                            Label(L("Restore"), systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("task.restore.\(session.sessionId)")
                    }
                    .listRowBackground(Theme.bg)
                }
                .listStyle(.plain)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(L("Hidden tasks"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
