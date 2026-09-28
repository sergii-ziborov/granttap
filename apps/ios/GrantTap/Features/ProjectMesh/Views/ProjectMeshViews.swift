import SwiftUI

/// A chat can arrive before its Project key and snapshot. Keep its Mesh door
/// visible so that a delayed publisher does not look like a missing feature.
struct ProjectMeshPendingView: View {
    let projectId: String
    let sessionId: String
    @ObservedObject var model: AppModel
    var onBack: (() -> Void)? = nil

    var body: some View {
        List {
            Section(L("Mesh")) {
                Label(L("Waiting for Mesh data from the computer"),
                      systemImage: "arrow.triangle.2.circlepath")
                if let route = model.chatComputerRoute(forSessionId: sessionId) {
                    CompatLabeledContent(L("Computer"), value: route.computerName)
                }
                Button(L("Refresh")) {
                    Task { await model.refreshSessions() }
                }
            }
        }
        .pageNavigationTitle(L("Mesh"), onBack: onBack)
    }
}

struct ProjectMeshView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }
    var onBack: (() -> Void)? = nil
    @State private var showReport = false
    @State private var showNewTask = false

    var currentSnapshot: ProjectMeshSnapshot {
        model.meshSnapshots[snapshot.projectId] ?? snapshot
    }

    /// Most recently worked first: the list says when each Task last moved,
    /// so the order follows the same clock.
    var orderedTasks: [ProjectMeshTask] {
        ProjectMeshRecency.ordered(currentSnapshot.tasks, snapshot: currentSnapshot, sessions: model.sessions)
    }

    var body: some View {
        let snapshot = currentSnapshot
        let rows = ProjectMeshRecency.rows(snapshot.tasks, snapshot: snapshot, sessions: model.sessions)
        List {
            Section(L("Mesh")) {
                ProjectDestinationRows(snapshot: snapshot, model: model)
            }
            Section {
                HStack {
                    count("Working", state: "working", rows: rows)
                    count("Blocked", state: "blocked", rows: rows)
                    count("Needs You", state: "needs_user", rows: rows)
                }
            }
            ProjectRepositoriesSection(snapshot: snapshot, model: model, onOpenSession: onOpenSession)
            ProjectRepositoryTaskSections(snapshot: snapshot, model: model, onOpenSession: onOpenSession)
        }
        .pageNavigationTitle(model.projectDisplayName(snapshot), onBack: onBack) {
            Button { showNewTask = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(L("New Task in this Mesh"))
            .accessibilityIdentifier("project.new-task")
            Button { showReport = true } label: {
                Image(systemName: "doc.text")
            }
            .accessibilityLabel(L("Report (PDF or CSV)…"))
            .accessibilityIdentifier("project.report")
        }
        #if !targetEnvironment(macCatalyst)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
        #endif
        .sheet(isPresented: $showReport) {
            ReportExportSheet(report: model.report(for: .project(currentSnapshot)))
        }
        .fullScreenCover(isPresented: $showNewTask) {
            ProjectNewTaskView(snapshot: currentSnapshot, model: model)
        }
        #if targetEnvironment(macCatalyst)
        .task(id: snapshot.projectId) {
            guard let reader = model.localMCPReader, reader.isReady,
                  reader.meshSnapshots[snapshot.projectId] != nil else { return }
            async let policy: Void = model.refreshLocalProjectPolicy(projectId: snapshot.projectId)
            async let approval: Void = model.refreshLocalProjectApproval(projectId: snapshot.projectId)
            if (try? await reader.enrichedMesh(projectId: snapshot.projectId)) != nil {
                model.refreshMacCombinedCatalog()
            }
            _ = await (policy, approval)
        }
        #endif
    }

    private func count(
        _ title: String, state: String, rows: [ProjectMeshRecency.Row]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(rows.filter { $0.state == state }.count)").font(.title2.bold())
            Text(L(title)).font(.caption).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func taskCount(_ state: String) -> Int {
        ProjectMeshRecency.rows(
            currentSnapshot.tasks, snapshot: currentSnapshot, sessions: model.sessions
        ).filter { $0.state == state }.count
    }

    func taskRow(_ task: ProjectMeshTask) -> ProjectMeshTaskRow {
        let row = ProjectMeshRecency.rows(
            [task], snapshot: currentSnapshot, sessions: model.sessions
        )[0]
        return ProjectMeshTaskRow(
            task: task, execution: row.execution, currentSession: row.session,
            presentedState: row.state, lastActiveAt: row.lastActiveAt
        )
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
