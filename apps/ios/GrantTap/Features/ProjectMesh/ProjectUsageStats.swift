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
        for execution in snapshot.executions {
            out[execution.sessionId] = execution.computerId
        }
        return out
    }

    static func perComputer(
        _ events: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot
    ) -> [ProjectComputerUsage] {
        let owner = computerBySession(snapshot)
        var grouped: [String: [CapabilityUsageEvent]] = [:]
        for event in events {
            guard let sessionId = event.sessionId, let computer = owner[sessionId] else { continue }
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

    /// Computers that belong to the Project even when no usage event exists.
    static func inventory(
        _ events: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot
    ) -> [ProjectComputerUsage] {
        let measured = Dictionary(uniqueKeysWithValues: perComputer(events, snapshot: snapshot).map { ($0.endpointId, $0) })
        return ProjectManagePresentation.endpointIds(snapshot).map { endpoint in
            measured[endpoint] ?? ProjectComputerUsage(
                endpointId: endpoint, calls: 0, failures: 0, cpuTimeMs: nil, peakMemoryBytes: nil
            )
        }
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

    /// Calls belonging to this Project, whichever computer made them.
    static func events(
        _ all: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot
    ) -> [CapabilityUsageEvent] {
        let ids = sessionIds(snapshot)
        return all.filter { $0.sessionId.map(ids.contains) == true }
    }
}
