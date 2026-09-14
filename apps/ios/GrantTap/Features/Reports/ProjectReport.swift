import Foundation

/// A report a person can hand to someone else: what a Project, a Task or a
/// chat cost, where it went wrong, and what it reached.
///
/// The screens answer these questions one at a time and only while the phone
/// is in hand. A report is the same facts assembled once, in a shape that
/// survives leaving the app: a CSV for a spreadsheet, a PDF for a person.
/// Nothing here is measured anew; every number is one the phone already holds.
struct ProjectReport: Equatable {
    struct Figure: Equatable, Identifiable {
        let label: String
        let value: String
        var note: String? = nil
        var id: String { label }
    }

    struct Table: Equatable, Identifiable {
        let title: String
        let columns: [String]
        let rows: [[String]]
        var footnote: String? = nil
        var id: String { title }
    }

    let title: String
    let subtitle: String
    let generatedAt: Date
    /// The first and last moment anything in the report happened.
    let periodStart: Date?
    let periodEnd: Date?
    let figures: [Figure]
    let tables: [Table]
    let notes: [String]

    /// "nodvox-report-20260906-0153": safe for a file name, specific enough to find.
    var fileStem: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = title.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return "\(name.isEmpty ? "granttap" : String(name.prefix(48)))-report-\(formatter.string(from: generatedAt))"
    }

    var periodLine: String {
        guard let periodStart, let periodEnd else { return L("No activity recorded yet") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: periodStart)) — \(formatter.string(from: periodEnd))"
    }
}

/// What a report is about. A chat is one session; a Task is every execution
/// it ever had; a Project is every Task on every computer.
enum ReportScope: Equatable {
    case project(ProjectMeshSnapshot)
    case task(ProjectMeshSnapshot, ProjectMeshTask)
    case chat(SessionInfo)

    var projectId: String? {
        switch self {
        case .project(let snapshot), .task(let snapshot, _): return snapshot.projectId
        case .chat(let session): return session.projectId
        }
    }
}

/// Everything the builder reads, handed in so a test can hand in the same.
struct ReportInputs {
    var sessions: [SessionInfo] = []
    var events: [CapabilityUsageEvent] = []
    var meshEvents: [ProjectMeshEvent] = []
    /// Load samples by computer name, oldest first.
    var loadHistory: [String: [LoadHistoryPoint]] = [:]
    /// The latest load report by computer name, for disk.
    var latestLoad: [String: MachineLoad] = [:]
    var computerName: (String) -> String = { $0 }
    /// The Project's name on this phone, which may be the person's own.
    var projectName: (ProjectMeshSnapshot) -> String = { $0.project.name }
    var now = Date()
}

enum ReportBuilder {
    /// Failed, cancelled, blocked, rejected, conflicting: the moments the work
    /// turned the wrong way, counted once each and listed later by name.
    static let wrongTurnEventTypes: Set<String> = ["TASK_BLOCKED", "HANDOFF_REJECTED", "CONFLICT"]

    static func build(_ scope: ReportScope, inputs: ReportInputs) -> ProjectReport {
        let executions = executions(for: scope)
        let sessionIds = sessionIds(for: scope, executions: executions)
        let sessions = uniqueSessions(inputs.sessions, ids: sessionIds)
        let events = inputs.events
            .filter { $0.sessionId.map(sessionIds.contains) == true }
            .sorted { $0.createdAt < $1.createdAt }
        let taskIds = taskIds(for: scope)
        let meshEvents = inputs.meshEvents
            .filter { taskIds.contains($0.taskId) && wrongTurnEventTypes.contains($0.eventType) }
            .sorted { $0.createdAt < $1.createdAt }

        let tokens = sessions.reduce(0) { $0 + $1.tokensSession }
        let failures = events.filter { $0.effectiveOutcome == .error }
        let cancelled = events.filter { $0.effectiveOutcome == .cancelled }
        let cpuMs = events.compactMap { $0.resource?.effectiveCpuTimeMs }.reduce(0, +)
        let peak = events.compactMap { $0.resource?.effectivePeakRssBytes }.max()
        let wallMs = executions.reduce(0.0) { $0 + max(0, $1.lastSeenAt - $1.startedAt) }
            + (executions.isEmpty ? sessions.reduce(0.0) { $0 + $1.elapsed * 1_000 } : 0)
        let wrongTurns = failures.count + cancelled.count + meshEvents.count

        var figures: [ProjectReport.Figure] = [
            .init(label: L("Tokens"), value: Format.tokens(tokens),
                  note: LPlural(sessions.count, one: "%d chat", many: "%d chats")),
            .init(label: L("Tool calls"), value: "\(events.count)",
                  note: failures.isEmpty ? nil : String(format: L("%d failed"), failures.count)),
            .init(label: L("Wrong turns"), value: "\(wrongTurns)",
                  note: L("failed, cancelled, blocked")),
            .init(label: L("CPU time"), value: cpuMs > 0 ? CapabilityResourceFormat.duration(cpuMs) : "—"),
            .init(label: L("Peak memory"), value: peak.map { CapabilityResourceFormat.bytes($0) } ?? "—"),
            .init(label: L("Wall time"), value: wallMs > 0 ? Format.duration(wallMs / 1_000) : "—"),
        ]
        let disk = diskFigure(executions: executions, sessions: sessions, latest: inputs.latestLoad)
        if let disk { figures.append(disk) }

        var tables: [ProjectReport.Table] = []
        tables.append(toolsTable(events))
        if let skills = kindTable(events, kind: .skill, title: L("Skills used")) { tables.append(skills) }
        if let servers = kindTable(events, kind: .mcp, title: L("MCP servers used")) { tables.append(servers) }
        if wrongTurns > 0 { tables.append(wrongTurnsTable(failures + cancelled, meshEvents: meshEvents)) }
        if !executions.isEmpty || !sessions.isEmpty {
            tables.append(executionsTable(executions, sessions: sessions, computerName: inputs.computerName))
        }
        if let load = loadTable(executions: executions, sessions: sessions, inputs: inputs) { tables.append(load) }

        let moments = events.map(\.createdAt) + executions.flatMap { [$0.startedAt, $0.lastSeenAt] }
            + sessions.flatMap { [$0.startedAt, $0.lastActivityAt] } + meshEvents.map(\.createdAt)
        return ProjectReport(
            title: title(for: scope, projectName: inputs.projectName),
            subtitle: subtitle(for: scope, computerName: inputs.computerName, projectName: inputs.projectName),
            generatedAt: inputs.now,
            periodStart: moments.min().map { Date(timeIntervalSince1970: $0 / 1_000) },
            periodEnd: moments.max().map { Date(timeIntervalSince1970: $0 / 1_000) },
            figures: figures, tables: tables,
            notes: [
                L("Tokens are the chats' own totals as the computer reported them. Tool calls, CPU and memory are what the computer measured around each call; the phone keeps the recent history only."),
                L("A wrong turn is a failed or cancelled call, a blocked Task, a rejected handoff, or a resource conflict."),
            ]
        )
    }

    // MARK: Scope

    static func executions(for scope: ReportScope) -> [ExecutionSessionLink] {
        switch scope {
        case .project(let snapshot): return ExecutionCoalescing.coalesced(snapshot.executions)
        case .task(let snapshot, let task):
            return ExecutionCoalescing.coalesced(snapshot.executions.filter { $0.taskId == task.taskId })
        case .chat: return []
        }
    }

    static func sessionIds(for scope: ReportScope, executions: [ExecutionSessionLink]) -> Set<String> {
        if case .chat(let session) = scope { return [session.sessionId] }
        return Set(executions.map(\.sessionId))
    }

    static func taskIds(for scope: ReportScope) -> Set<String> {
        switch scope {
        case .project(let snapshot): return Set(snapshot.tasks.map(\.taskId))
        case .task(_, let task): return [task.taskId]
        case .chat(let session): return session.taskId.map { [$0] } ?? []
        }
    }

    static func uniqueSessions(_ all: [SessionInfo], ids: Set<String>) -> [SessionInfo] {
        var seen = Set<String>()
        return all.filter { ids.contains($0.sessionId) && seen.insert($0.sessionId).inserted }
    }

    static func title(for scope: ReportScope, projectName: (ProjectMeshSnapshot) -> String = { $0.project.name }) -> String {
        switch scope {
        case .project(let snapshot): return projectName(snapshot)
        case .task(_, let task): return task.title
        case .chat(let session): return session.displayTitle
        }
    }

    static func subtitle(
        for scope: ReportScope, computerName: (String) -> String,
        projectName: (ProjectMeshSnapshot) -> String = { $0.project.name }
    ) -> String {
        switch scope {
        case .project(let snapshot):
            let computers = ProjectManagePresentation.endpointIds(snapshot).map(computerName)
            return [L("Project report"), computers.isEmpty ? nil : computers.joined(separator: ", ")]
                .compactMap { $0 }.joined(separator: " · ")
        case .task(let snapshot, _):
            return "\(L("Task report")) · \(projectName(snapshot))"
        case .chat(let session):
            return [L("Chat report"), AgentIdentity.displayName(session.agent), session.computerId.map(computerName)]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }
}
