import SwiftUI

struct ProjectMeshView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }
    @State private var showReport = false
    @State private var showWriteToAgents = false

    /// Most recently worked first: the list says when each Task last moved,
    /// so the order follows the same clock.
    var orderedTasks: [ProjectMeshTask] {
        ProjectMeshRecency.ordered(snapshot.tasks, snapshot: snapshot, sessions: model.sessions)
    }

    var body: some View {
        List {
            Section {
                Button {
                    showWriteToAgents = true
                } label: {
                    ProjectDestinationLabel(
                        title: L("Write to agents"),
                        detail: L("Send through the existing task delivery"),
                        icon: "square.and.pencil"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("project.write-to-agents")
                ForEach(activeExecutors) { execution in
                    NavigationLink {
                        TaskRouteView(
                            route: .init(projectId: snapshot.projectId, taskId: execution.taskId),
                            model: model, onOpenSession: onOpenSession,
                            presentedAsSheet: false
                        )
                    } label: {
                        executorRow(execution)
                    }
                }
                HStack {
                    count("Working", state: "working")
                    count("Blocked", state: "blocked")
                    count("Needs You", state: "needs_user")
                }
                ForEach(orderedTasks) { task in
                    NavigationLink {
                        TaskRouteView(
                            route: .init(projectId: snapshot.projectId, taskId: task.taskId),
                            model: model, onOpenSession: onOpenSession,
                            presentedAsSheet: false
                        )
                    } label: {
                        taskRow(task)
                    }
                }
            } header: {
                Text(L("Working"))
            } footer: {
                if !snapshot.tasks.isEmpty {
                    Text(L("Most recently worked first."))
                }
            }
            Section(L("Project")) {
                ProjectDestinationRows(snapshot: snapshot, model: model)
            }
            ProjectRepositoriesSection(snapshot: snapshot, model: model, onOpenSession: onOpenSession)
        }
        .navigationTitle(model.projectDisplayName(snapshot))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showReport = true
                } label: {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel(L("Report (PDF or CSV)…"))
                .accessibilityIdentifier("project.report")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
        .sheet(isPresented: $showReport) {
            ReportExportSheet(report: model.report(for: .project(snapshot)))
        }
        .sheet(isPresented: $showWriteToAgents) {
            ProjectWriteToAgentsSheet(snapshot: snapshot, model: model)
        }
    }

    var activeExecutors: [ExecutionSessionLink] {
        snapshot.executions.filter { $0.endedAt == nil }
            .sorted {
                if $0.lastSeenAt != $1.lastSeenAt { return $0.lastSeenAt > $1.lastSeenAt }
                return $0.id < $1.id
            }
    }

    func executorRow(_ execution: ExecutionSessionLink) -> some View {
        let task = snapshot.tasks.first { $0.taskId == execution.taskId }
        return VStack(alignment: .leading, spacing: 3) {
            Text(MeshActorPresentation.executionName(execution))
            if let task {
                Text(ProjectMeshTaskTitle.text(task, session: model.sessions.first {
                    $0.sessionId == execution.sessionId
                }))
                .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityIdentifier("project.executor.\(execution.sessionId)")
    }

    private func count(_ title: String, state: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(taskCount(state))").font(.title2.bold())
            Text(L(title)).font(.caption).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func taskCount(_ state: String) -> Int {
        snapshot.tasks.filter { taskState($0) == state }.count
    }

    func taskRow(_ task: ProjectMeshTask) -> ProjectMeshTaskRow {
        let execution = snapshot.executions.first {
            $0.taskId == task.taskId && $0.sessionId == task.ownerSessionId
        }
        let session = execution.flatMap { owner in
            model.sessions.first { $0.sessionId == owner.sessionId }
        }
        return ProjectMeshTaskRow(
            task: task, execution: execution, currentSession: session,
            presentedState: ProjectMeshTaskPresentation.state(
                task: task, execution: execution, currentSession: session
            ),
            lastActiveAt: ProjectMeshRecency.lastActiveAt(task, snapshot: snapshot, sessions: model.sessions)
        )
    }

    private func taskState(_ task: ProjectMeshTask) -> String {
        let row = taskRow(task)
        return row.presentedState ?? task.state
    }
}

struct ProjectMeshTaskRow: View {
    let task: ProjectMeshTask
    let execution: ExecutionSessionLink?
    var currentSession: SessionInfo? = nil
    var presentedState: String? = nil
    /// When any execution of this Task last did anything, epoch milliseconds.
    var lastActiveAt: Double? = nil

    var stateLabel: String {
        ProjectMeshTaskPresentation.label(
            presentedState ?? ProjectMeshTaskPresentation.state(
                task: task, execution: execution, currentSession: currentSession
            )
        )
    }

    var detailLine: String {
        [stateLabel, execution.map(MeshActorPresentation.executionName)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "Last active 2 h ago", from the Task's own executions.
    var recencyLine: String? {
        guard let lastActiveAt, lastActiveAt > 0 else { return nil }
        let seconds = Int(max(0, Date().timeIntervalSince1970 - lastActiveAt / 1_000))
        return "\(L("Last active")) \(ConnectionLoadFormat.age(seconds: seconds))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ProjectMeshTaskTitle.text(task, session: currentSession)).font(.headline)
            Text(detailLine).font(.caption).foregroundStyle(Theme.muted)
            if let recencyLine {
                Text(recencyLine).font(.caption2).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("task.recency.\(task.taskId)")
            }
        }
    }
}

/// When a Task last moved, from every execution it has had and the chat that
/// owns it now, so a list can be read as a timeline.
enum ProjectMeshRecency {
    static func lastActiveAt(
        _ task: ProjectMeshTask, snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]
    ) -> Double {
        let executions = snapshot.executions.filter { $0.taskId == task.taskId }
        let fromExecutions = executions.map(\.lastSeenAt)
        let fromSessions = executions.compactMap { execution in
            sessions.first { $0.sessionId == execution.sessionId }?.lastActivityAt
        }
        return (fromExecutions + fromSessions + [task.updatedAt]).max() ?? task.updatedAt
    }

    static func ordered(
        _ tasks: [ProjectMeshTask], snapshot: ProjectMeshSnapshot, sessions: [SessionInfo]
    ) -> [ProjectMeshTask] {
        var stamped: [(task: ProjectMeshTask, at: Double)] = []
        for task in tasks {
            stamped.append((task, lastActiveAt(task, snapshot: snapshot, sessions: sessions)))
        }
        stamped.sort { left, right in
            if left.at != right.at { return left.at > right.at }
            return left.task.taskId < right.task.taskId
        }
        return stamped.map(\.task)
    }
}

enum ProjectMeshTaskPresentation {
    static func state(
        task: ProjectMeshTask,
        execution: ExecutionSessionLink?,
        currentSession: SessionInfo?
    ) -> String {
        if ["blocked", "needs_user", "handoff", "completed", "failed"].contains(task.state) {
            return task.state
        }
        if currentSession?.isPaused == true { return "paused" }
        if let native = currentSession?.state {
            switch native {
            case "working": return "working"
            case "waiting": return "needs_user"
            default: return "planned"
            }
        }
        if execution?.endedAt != nil, task.state == "working" { return "planned" }
        return task.state
    }

    static func label(_ state: String) -> String {
        switch state {
        case "working": return L("Working")
        case "blocked": return L("Blocked")
        case "needs_user": return L("Needs You")
        case "paused": return L("Paused")
        case "handoff": return L("Handoff")
        case "completed": return L("Finished")
        case "failed": return L("Failed")
        default: return L("Idle")
        }
    }
}

enum MeshActorPresentation {
    static func name(_ actorId: String) -> String {
        actorId.split(separator: "-").map { part in
            part.lowercased() == "qa" ? "QA" : part.capitalized
        }.joined(separator: " ")
    }

    static func routeName(provider: String, actorId: String?) -> String {
        guard provider == "grok_bot", let actorId else {
            return AgentIdentity.displayName(provider)
        }
        return "\(name(actorId)) · Grok Bot"
    }

    static func executionName(_ execution: ExecutionSessionLink) -> String {
        guard execution.provider == "grok_bot", let actorId = execution.actorId else {
            return "\(AgentIdentity.displayName(execution.provider)) · \(execution.computerId)"
        }
        return "\(name(actorId)) · Grok Bot"
    }
}
