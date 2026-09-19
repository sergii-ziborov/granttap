import Foundation

/// How this phone treats a computer inside one Project.
enum ProjectComputerDisposition: String, Equatable {
    case active
    case archived
    case removed
}

/// The computers a Project can run on, archive, or take out — bindings,
/// live executions, and pairing rooms that already hold the mesh key.
enum ProjectComputerRoster {
    /// Bindings and open work, plus rooms that already hold this Project key.
    static func knownIds(
        snapshot: ProjectMeshSnapshot,
        participating: Set<String> = [],
        memberRooms: Set<String> = []
    ) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for id in ProjectManagePresentation.endpointIds(snapshot)
            + participating.filter { !memberRooms.contains($0) }.sorted()
        {
            if seen.insert(id).inserted { ids.append(id) }
        }
        return ids
    }

    /// Computers that can take new work: still in the Project, not archived.
    static func hostIds(
        snapshot: ProjectMeshSnapshot,
        participating: Set<String> = [],
        memberRooms: Set<String> = [],
        archived: Set<String> = [],
        removed: Set<String> = []
    ) -> [String] {
        knownIds(snapshot: snapshot, participating: participating, memberRooms: memberRooms)
            .filter { !archived.contains($0) && !removed.contains($0) }
    }

    static func memberIds(
        snapshot: ProjectMeshSnapshot,
        participating: Set<String> = [],
        memberRooms: Set<String> = [],
        hidden: Set<String> = []
    ) -> [String] {
        knownIds(snapshot: snapshot, participating: participating, memberRooms: memberRooms)
            .filter { !hidden.contains($0) }
    }

    static func archivedIds(
        snapshot: ProjectMeshSnapshot,
        archived: Set<String>
    ) -> [String] {
        knownIds(snapshot: snapshot).filter(archived.contains)
            + archived.subtracting(Set(knownIds(snapshot: snapshot))).sorted()
    }

    static func disposition(
        _ endpointId: String, archived: Set<String>, removed: Set<String>
    ) -> ProjectComputerDisposition {
        if removed.contains(endpointId) { return .removed }
        if archived.contains(endpointId) { return .archived }
        return .active
    }
}

enum ProjectMeshStatsPresentation {
    static func summary(
        snapshot: ProjectMeshSnapshot,
        events: [CapabilityUsageEvent],
        sessions: [SessionInfo],
        computerCount: Int
    ) -> String {
        let sessionIds = ProjectUsageStats.sessionIds(snapshot)
        let projectEvents = ProjectUsageStats.events(events, snapshot: snapshot)
        let tokens = ProjectUsageStats.tokens(sessions, sessionIds: sessionIds)
        let computers = String(
            format: L(computerCount == 1 ? "%d computer" : "%d computers"), computerCount
        )
        if projectEvents.isEmpty && tokens == 0 {
            return computers
        }
        let calls = String(
            format: L(projectEvents.count == 1 ? "%d call" : "%d calls"), projectEvents.count
        )
        if tokens == 0 { return "\(computers) · \(calls)" }
        return "\(computers) · \(calls) · \(Format.tokens(tokens))"
    }

    static func taskCount(_ snapshot: ProjectMeshSnapshot, state: String) -> Int {
        snapshot.tasks.filter { $0.state == state }.count
    }
}
