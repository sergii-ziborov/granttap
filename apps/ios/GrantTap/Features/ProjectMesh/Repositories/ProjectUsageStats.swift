import Foundation

/// What one computer contributed to a Project.
struct ProjectComputerUsage: Identifiable, Equatable {
    let endpointId: String
    let calls: Int
    let failures: Int
    let cpuTimeMs: Int?
    let peakMemoryBytes: Int?

    var id: String { endpointId }
}

/// What a Project costs, across every computer working on it.
///
/// A task answers "what did this run cost" and Usage answers "what has this
/// computer been doing". Neither can answer "what does this Project cost",
/// because a Project is the only scope that spans several machines — and the
/// question that matters about it is usually which machine is carrying it.
enum ProjectUsageStats {
    /// Session ids belonging to this Project, across providers and computers.
    static func sessionIds(_ snapshot: ProjectMeshSnapshot) -> Set<String> {
        Set(snapshot.executions.map(\.sessionId))
    }

    /// Which computer ran which session, so a call can be credited to a machine.
    static func computerBySession(_ snapshot: ProjectMeshSnapshot) -> [String: String] {
        var out: [String: String] = [:]
        var ambiguous = Set<String>()
        for execution in snapshot.executions {
            if let previous = out[execution.sessionId], previous != execution.computerId {
                ambiguous.insert(execution.sessionId)
            } else {
                out[execution.sessionId] = execution.computerId
            }
        }
        for sessionId in ambiguous { out.removeValue(forKey: sessionId) }
        return out
    }

    static func perComputer(
        _ events: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot,
        roomByEndpointId: [String: String]
    ) -> [ProjectComputerUsage] {
        let scoped = self.events(events, snapshot: snapshot, roomByEndpointId: roomByEndpointId)
        var grouped: [String: [CapabilityUsageEvent]] = [:]
        for event in scoped {
            guard let room = event.sourceRoom, let sessionId = event.sessionId,
                  let agent = event.agent else { continue }
            let endpoints = Set(snapshot.executions.filter {
                $0.sessionId == sessionId && $0.provider == agent
                    && roomByEndpointId[$0.computerId] == room
            }.map(\.computerId))
            guard endpoints.count == 1, let computer = endpoints.first else { continue }
            grouped[computer, default: []].append(event)
        }
        return grouped.map { computer, rows in
            let cpu = rows.compactMap { $0.resource?.effectiveCpuTimeMs }
            return ProjectComputerUsage(
                endpointId: computer,
                calls: rows.count,
                failures: rows.filter { $0.effectiveOutcome == .error }.count,
                // CPU is spent per call and adds up across them.
                cpuTimeMs: cpu.isEmpty ? nil : cpu.reduce(0, +),
                // Memory is a level, so the machine's worst moment is the peak.
                peakMemoryBytes: rows.compactMap { $0.resource?.effectivePeakRssBytes }.max()
            )
        }
        // The machine carrying the Project reads first.
        .sorted { $0.calls == $1.calls ? $0.endpointId < $1.endpointId : $0.calls > $1.calls }
    }

    /// Tokens the chats spent, added up: each chat carries its own total, and a
    /// Project or a computer is the sum of the chats it holds.
    static func tokens(_ sessions: [SessionInfo], sessionIds: Set<String>) -> Int {
        var seen = Set<String>()
        return sessions.reduce(0) { total, session in
            guard sessionIds.contains(session.sessionId),
                  seen.insert(session.sessionId).inserted else { return total }
            return total + session.tokensSession
        }
    }

    /// A missing session report is unknown, not measured zero tokens.
    static func reportedTokens(_ sessions: [SessionInfo], sessionIds: Set<String>) -> Int? {
        guard sessions.contains(where: { sessionIds.contains($0.sessionId) }) else { return nil }
        return tokens(sessions, sessionIds: sessionIds)
    }

    /// Attribute reported chat totals only to the matching Project execution.
    static func reportedTokens(
        _ sessions: [SessionInfo], snapshot: ProjectMeshSnapshot, endpointId: String? = nil
    ) -> Int? {
        let executions = snapshot.executions.filter {
            endpointId == nil || $0.computerId == endpointId
        }
        var seen = Set<String>()
        var total = 0
        for session in sessions {
            if let projectId = session.projectId, projectId != snapshot.projectId { continue }
            let matching = executions.filter {
                $0.sessionId == session.sessionId && $0.provider == session.agent
                    && (session.computerId == nil || $0.computerId == session.computerId)
            }
            guard let execution = matching.first else { continue }
            if session.computerId == nil {
                let endpoints = Set(snapshot.executions.filter {
                    $0.sessionId == session.sessionId && $0.provider == session.agent
                }.map(\.computerId))
                if endpoints.count != 1 { continue }
            }
            guard seen.insert(execution.id).inserted else { continue }
            total += session.tokensSession
        }
        return seen.isEmpty ? nil : total
    }

    /// Calls belonging to this Project, whichever computer made them.
    static func events(
        _ all: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot,
        roomByEndpointId: [String: String], taskId: String? = nil,
        endpointId: String? = nil
    ) -> [CapabilityUsageEvent] {
        let executionKeys = Set(snapshot.executions.compactMap { execution -> String? in
            guard (taskId == nil || execution.taskId == taskId),
                  (endpointId == nil || execution.computerId == endpointId),
                  let room = roomByEndpointId[execution.computerId] else { return nil }
            return [room, execution.provider, execution.sessionId].joined(separator: "\u{1f}")
        })
        return all.filter { event in
            guard let room = event.sourceRoom, let agent = event.agent,
                  let sessionId = event.sessionId else { return false }
            return executionKeys.contains([room, agent, sessionId].joined(separator: "\u{1f}"))
        }
    }

    static func totals(
        _ events: [CapabilityUsageEvent]
    ) -> (calls: Int, failures: Int, peakMemoryBytes: Int?, cpuTimeMs: Int?)? {
        guard !events.isEmpty else { return nil }
        let cpu = events.compactMap { $0.resource?.effectiveCpuTimeMs }
        return (
            calls: events.count,
            failures: events.filter { $0.effectiveOutcome == .error }.count,
            peakMemoryBytes: events.compactMap { $0.resource?.effectivePeakRssBytes }.max(),
            cpuTimeMs: cpu.isEmpty ? nil : cpu.reduce(0, +)
        )
    }
}
