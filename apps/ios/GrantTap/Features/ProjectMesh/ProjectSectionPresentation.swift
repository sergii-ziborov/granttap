import Foundation

/// Compact Knowledge facts already on the phone: capsule decisions, runtime
/// attempts, and the context a Task Capsule already carries. Nothing here is
/// invented when the journal is empty.
enum ProjectKnowledgePresentation {
    struct Summary: Equatable {
        let decisions: [String]
        let attempts: [String]
        let source: String?
        let freshnessMs: Double?
        let agentContext: [String]
        let generatedAt: Double

        var isEmpty: Bool {
            decisions.isEmpty && attempts.isEmpty && agentContext.isEmpty
        }

        var rowDetail: String {
            if isEmpty { return L("Nothing recorded yet") }
            var parts: [String] = []
            if !decisions.isEmpty {
                parts.append(String(
                    format: L(decisions.count == 1 ? "%d decision" : "%d decisions"),
                    decisions.count
                ))
            }
            if !attempts.isEmpty {
                parts.append(String(
                    format: L(attempts.count == 1 ? "%d attempt" : "%d attempts"),
                    attempts.count
                ))
            }
            if parts.isEmpty, !agentContext.isEmpty {
                parts.append(L("Context for agents"))
            }
            if let freshnessMs {
                let seconds = Int(max(0, Date().timeIntervalSince1970 - freshnessMs / 1_000))
                parts.append("\(L("Updated")) \(ConnectionLoadFormat.age(seconds: seconds))")
            }
            return parts.joined(separator: " · ")
        }

        var freshnessLine: String? {
            guard let freshnessMs, freshnessMs > 0 else { return nil }
            return ReportBuilder.stamp(freshnessMs)
        }
    }

    static func invocations(
        from history: [String: [ProjectInvocationRecord]],
        projectId: String,
        taskIds: [String]
    ) -> [ProjectInvocationRecord] {
        taskIds.flatMap { taskId in
            history["\(projectId)\u{1f}\(taskId)"] ?? []
        }
        .sorted {
            if $0.event.occurred_at != $1.event.occurred_at {
                return $0.event.occurred_at > $1.event.occurred_at
            }
            return $0.id < $1.id
        }
    }

    static func summary(
        snapshot: ProjectMeshSnapshot,
        invocations: [ProjectInvocationRecord] = [],
        nowMs: Double = Date().timeIntervalSince1970 * 1_000
    ) -> Summary {
        _ = nowMs
        let capsules = snapshot.events.compactMap(\.payload.capsule)
        var seenDecisions = Set<String>()
        var decisions: [String] = []
        for text in capsules.flatMap(\.importantDecisions) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seenDecisions.insert(clean).inserted else { continue }
            decisions.append(clean)
        }

        var attempts: [String] = []
        var seenAttempts = Set<String>()
        for record in invocations.prefix(32) {
            let line = [
                record.event.tool_name,
                phaseLabel(record.event.phase),
                record.event.source,
            ].joined(separator: " · ")
            guard seenAttempts.insert(line).inserted else { continue }
            attempts.append(line)
        }
        for event in snapshot.events where ReportBuilder.wrongTurnEventTypes.contains(event.eventType) {
            let line = [
                ReportBuilder.meshLabel(event.eventType),
                event.payload.summary ?? event.payload.reason,
            ].compactMap { $0 }.joined(separator: " · ")
            guard !line.isEmpty, seenAttempts.insert(line).inserted else { continue }
            attempts.append(line)
        }

        var seenContext = Set<String>()
        var agentContext: [String] = []
        for task in snapshot.tasks {
            let goal = task.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goal.isEmpty, seenContext.insert(goal).inserted {
                agentContext.append(goal)
            }
        }
        for text in capsules.flatMap(\.remainingWork) + capsules.flatMap(\.importantDecisions) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seenContext.insert(clean).inserted else { continue }
            agentContext.append(clean)
        }

        let latestInvocation = invocations.map(\.event.occurred_at).max()
        let freshness = [latestInvocation, snapshot.generatedAt].compactMap { $0 }.max()
        let source = invocations.first.map { sourceLabel($0.event.source) }
            ?? L("Project snapshot")
        return Summary(
            decisions: Array(decisions.prefix(16)),
            attempts: Array(attempts.prefix(32)),
            source: source,
            freshnessMs: freshness,
            agentContext: Array(agentContext.prefix(16)),
            generatedAt: snapshot.generatedAt
        )
    }

    static func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "requested": return L("Requested")
        case "reported_success": return L("Reported success")
        case "reported_failure": return L("Reported failure")
        case "reported_unknown": return L("Outcome unknown")
        case "denied": return L("Denied")
        case "change_observed": return L("Change verified")
        case "source_gap": return L("History gap")
        default: return L("Unknown")
        }
    }

    static func sourceLabel(_ source: String) -> String {
        switch source {
        case "transcript": return L("Agent transcript")
        case "hook": return L("Computer hook")
        case "filesystem": return L("Filesystem")
        case "scanner": return L("Scanner")
        default: return source
        }
    }
}

/// Shared Skills from the Project snapshot, plus MCP servers the Project's
/// chats already reported. Missing usage is unknown — never "proven unused".
/// Listing a skill does not grant permission.
enum ProjectToolsSkillsPresentation {
    enum Kind: String, Equatable {
        case skill
        case mcp
    }

    struct Item: Equatable, Identifiable {
        let kind: Kind
        let name: String
        let state: String
        var version: String? = nil
        var digest: String? = nil
        var source: String? = nil
        var description: String? = nil
        var id: String { "\(kind.rawValue)\u{1f}\(name)" }

        var stateLabel: String { ProjectToolsSkillsPresentation.stateLabel(state) }

        var detail: String {
            let desired = version.map { "\(L("Desired")) \($0)" }
            let digestShort = digest.map { $0.count > 12 ? String($0.prefix(12)) : $0 }
            return [desired, digestShort, source, description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }

    struct Catalog: Equatable {
        var skills: [Item]
        var servers: [Item]
        var incomplete: Bool
        var usedNames: Set<String>

        var isEmpty: Bool { skills.isEmpty && servers.isEmpty }

        var skillCount: Int { skills.count }
        var mcpCount: Int { servers.count }

        var rowDetail: String {
            if isEmpty {
                return incomplete ? L("Incomplete · none reported") : L("None reported")
            }
            var parts: [String] = []
            if skillCount > 0 {
                parts.append(String(
                    format: L(skillCount == 1 ? "%d skill" : "%d skills"), skillCount
                ))
            }
            if mcpCount > 0 {
                parts.append(String(
                    format: L(mcpCount == 1 ? "%d MCP server" : "%d MCP servers"), mcpCount
                ))
            }
            if incomplete { parts.append(L("incomplete")) }
            return parts.joined(separator: " · ")
        }

        func items(kind: Kind, state: String) -> [Item] {
            let pool = kind == .skill ? skills : servers
            return pool.filter { $0.state == state }
        }
    }

    static let states = ["installed", "available", "used", "unknown"]

    static func stateLabel(_ state: String) -> String {
        switch normalizedState(state) {
        case "installed": return L("Installed")
        case "available": return L("Available")
        case "used": return L("Used")
        default: return L("Unknown")
        }
    }

    static func normalizedState(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return states.contains(value) ? value : "unknown"
    }

    /// Project snapshot skills first. Session SkillInfo is not copied into this
    /// list — empty chat skills still show the Project catalog, and the catalog
    /// is never injected into a chat prompt from here.
    static func catalog(
        snapshot: ProjectMeshSnapshot,
        sessions: [SessionInfo] = [],
        usage: [CapabilityUsageEvent] = []
    ) -> Catalog {
        let sessionIds = ProjectUsageStats.sessionIds(snapshot)
        let projectSessions = sessions.filter {
            $0.projectId == snapshot.projectId || sessionIds.contains($0.sessionId)
        }
        let projectUsage = ProjectUsageStats.events(usage, snapshot: snapshot)
        let usedSkills = Set(projectUsage.filter { $0.kind == .skill }.map(\.name))
        let usedServers = Set(projectUsage.filter { $0.kind == .mcp }.map(\.name))

        var skills = (snapshot.skills ?? []).map { skill in
            Item(
                kind: .skill,
                name: skill.name,
                state: normalizedState(skill.state),
                version: skill.version,
                digest: skill.digest,
                source: skill.source,
                description: skill.description
            )
        }
        let catalogNames = Set(skills.map(\.name))
        for name in usedSkills.sorted() where !catalogNames.contains(name) {
            skills.append(Item(kind: .skill, name: name, state: "used"))
        }

        var serversByName: [String: Item] = [:]
        for session in projectSessions {
            for server in session.mcpServers ?? [] {
                let state = server.configuredEnabled ? "installed" : "available"
                let current = serversByName[server.name]
                let next = Item(
                    kind: .mcp,
                    name: server.name,
                    state: current?.state == "installed" ? "installed" : state,
                    version: server.version ?? current?.version,
                    source: server.metadataSource ?? current?.source,
                    description: server.title ?? current?.description
                )
                serversByName[server.name] = next
            }
        }
        for name in usedServers where serversByName[name] == nil {
            serversByName[name] = Item(kind: .mcp, name: name, state: "used")
        }

        return Catalog(
            skills: skills.sorted { $0.name < $1.name },
            servers: serversByName.values.sorted { $0.name < $1.name },
            incomplete: snapshot.incomplete == true,
            usedNames: usedSkills.union(usedServers)
        )
    }

    /// Usage evidence, when present. Absence is unknown — never unused.
    static func usageLabel(name: String, usedNames: Set<String>) -> String? {
        if usedNames.contains(name) { return L("Used") }
        return L("Unknown")
    }
}

enum ProjectMeshActivityWindow {
    static let liveMs: Double = 60 * 60 * 1_000

    static func isActiveInLastHour(lastSeenAt: Double, now: Double) -> Bool {
        now - lastSeenAt <= liveMs
    }
}

enum ProjectOverviewPresentation {
    struct AttentionItem: Identifiable, Equatable {
        let eventId: String
        let taskId: String
        let title: String
        var id: String { eventId }
    }

    static func attention(
        snapshot: ProjectMeshSnapshot,
        events: [ProjectMeshEvent]
    ) -> [AttentionItem] {
        events.filter { $0.projectId == snapshot.projectId }.map { event in
            let task = snapshot.tasks.first { $0.taskId == event.taskId }
            let text = event.payload.question
                ?? event.payload.reason
                ?? event.payload.summary
                ?? event.eventType
            return AttentionItem(
                eventId: event.eventId,
                taskId: event.taskId,
                title: [task.map { ProjectMeshTaskTitle.text($0, session: nil) }, text]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
    }

    static func recipientCount(_ snapshot: ProjectMeshSnapshot) -> Int {
        snapshot.executions.filter { $0.endedAt == nil }.count
    }

    static func writeDetail(_ snapshot: ProjectMeshSnapshot) -> String {
        LPlural(recipientCount(snapshot), one: "%d recipient", many: "%d recipients")
    }

    static func workFields(
        task: ProjectMeshTask,
        execution: ExecutionSessionLink?,
        lastActiveAt: Double?,
        now: Double = Date().timeIntervalSince1970 * 1_000
    ) -> [String] {
        var fields: [String] = []
        if let owner = task.ownerSessionId { fields.append("\(L("Owner")) \(owner)") }
        if let execution {
            fields.append("\(L("Agent")) \(MeshActorPresentation.executionName(execution))")
            fields.append("\(L("Computer")) \(execution.computerId)")
            if let branch = execution.branch, !branch.isEmpty {
                fields.append("\(L("Branch")) \(branch)")
            }
        }
        _ = (lastActiveAt, now)
        return fields
    }
}

enum TaskContextPresentation {
    struct Card: Equatable {
        let title: String
        let goal: String?
        let revision: String?
        let sources: [String]
        let decisions: [String]
        let missing: [String]
        let sizeLabel: String
        let offered: Bool
        let issued: Bool
        let confirmed: Bool
    }

    static func card(
        task: ProjectMeshTask?,
        snapshot: ProjectMeshSnapshot,
        events: [ProjectMeshEvent],
        invocations: [ProjectInvocationRecord] = []
    ) -> Card {
        let knowledge = ProjectKnowledgePresentation.summary(
            snapshot: snapshot,
            invocations: invocations
        )
        let taskEvents = events.filter { $0.taskId == task?.taskId }
        let offered = taskEvents.contains {
            $0.eventType == "AGENT_QUESTION" || $0.eventType == "HANDOFF_REQUEST"
        }
        let issued = !invocations.isEmpty || taskEvents.contains { $0.eventType == "TASK_PROGRESS" }
        let confirmed = invocations.contains { $0.event.phase == "change_observed" }
        let missing = task.map { item in
            [
                item.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Goal") : nil,
                item.revision == nil ? L("Revision") : nil,
            ].compactMap { $0 }
        } ?? [L("Task")]
        return Card(
            title: task.map { ProjectMeshTaskTitle.text($0, session: nil) } ?? L("Task"),
            goal: task?.goal,
            revision: task?.revision.map { String(Int($0)) },
            sources: [knowledge.source].compactMap { $0 },
            decisions: Array(knowledge.decisions.prefix(4)),
            missing: missing,
            sizeLabel: String(format: L("%d events shown"), min(taskEvents.count, 8)),
            offered: offered,
            issued: issued,
            confirmed: confirmed
        )
    }

    static func deliveryLabel(offered: Bool, issued: Bool, confirmed: Bool) -> String {
        if confirmed { return L("Confirmed by client") }
        if issued { return L("Issued via MCP") }
        if offered { return L("Offered to agent") }
        return L("Not yet offered")
    }
}
