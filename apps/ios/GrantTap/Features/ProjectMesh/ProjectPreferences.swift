import Foundation

/// What this phone decided about a Project: what to call it, whether to show it.
///
/// A Project's name comes from the repository folder on the computer that
/// reported it, and every Project a computer ever reported stays. Neither is
/// this phone's decision to make on the computer, so both are kept here: a
/// name of the person's own, and a hidden mark for a Project that is over,
/// duplicated, or simply not theirs to watch.
struct ProjectPreference: Codable, Equatable {
    var customName: String? = nil
    var hidden = false
    var hiddenAt: Double? = nil

    var isEmpty: Bool { customName == nil && !hidden }
}

enum ProjectPreferencesStore {
    static let key = "granttap.project-preferences"

    static func load(defaults: UserDefaults = .standard) -> [String: ProjectPreference] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ProjectPreference].self, from: data) else { return [:] }
        return decoded
    }

    static func save(_ preferences: [String: ProjectPreference], defaults: UserDefaults = .standard) {
        let kept = preferences.filter { !$0.value.isEmpty }
        if kept.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(kept) {
            defaults.set(data, forKey: key)
        }
    }
}

/// One row of the Projects list: what a Project is up to, at a glance.
struct ProjectListRow: Identifiable, Equatable {
    let projectId: String
    let name: String
    let repositoryLeaf: String
    let computers: Int
    let openTasks: Int
    let working: Int
    let needsYou: Int
    let members: Int
    let holdsKey: Bool
    let hidden: Bool
    let lastActiveAt: Double
    /// The person whose phone shares this Project with this one, when it is
    /// theirs and not this phone's own.
    var sharedBy: String? = nil
    var id: String { projectId }

    /// "nodvox · 2 computers · 3 open · 1 needs you"
    var detail: String {
        var parts: [String] = []
        if !repositoryLeaf.isEmpty, repositoryLeaf.lowercased() != name.lowercased() { parts.append(repositoryLeaf) }
        parts.append(LPlural(computers, one: "%d computer", many: "%d computers"))
        if openTasks > 0 { parts.append(LPlural(openTasks, one: "%d open task", many: "%d open tasks")) }
        if members > 0 { parts.append(LPlural(members, one: "%d member", many: "%d members")) }
        return parts.joined(separator: " · ")
    }
}

enum ProjectsCatalog {
    /// Every Project the phone knows, the busiest first, hidden ones last.
    static func rows(
        snapshots: [ProjectMeshSnapshot], sessions: [SessionInfo], preferences: [String: ProjectPreference],
        memberLinks: [MemberLink], rooms: [String: Set<String>], connections: [LinkedComputer] = [],
        now: Double = Date().timeIntervalSince1970 * 1_000
    ) -> [ProjectListRow] {
        let rows = snapshots.map { snapshot -> ProjectListRow in
            let preference = preferences[snapshot.projectId]
            let states = snapshot.tasks.map { task -> String in
                let execution = snapshot.executions.first { $0.taskId == task.taskId && $0.sessionId == task.ownerSessionId }
                let session = execution.flatMap { owner in sessions.first { $0.sessionId == owner.sessionId } }
                return ProjectMeshTaskPresentation.state(task: task, execution: execution, currentSession: session)
            }
            let lastActive = snapshot.tasks.map { ProjectMeshRecency.lastActiveAt($0, snapshot: snapshot, sessions: sessions) }.max()
                ?? snapshot.generatedAt
            return ProjectListRow(
                projectId: snapshot.projectId,
                name: displayName(snapshot, preference: preference),
                repositoryLeaf: ProjectRepositories.repositoryLeaf(snapshot.project.canonicalRepositoryId),
                computers: ProjectManagePresentation.endpointIds(snapshot).count,
                openTasks: snapshot.tasks.filter { !["completed", "failed"].contains($0.state) }.count,
                working: states.filter { $0 == "working" }.count,
                needsYou: states.filter { $0 == "needs_user" || $0 == "blocked" }.count,
                members: memberLinks.filter { $0.projectId == snapshot.projectId }.count,
                holdsKey: !(rooms[snapshot.projectId] ?? []).isEmpty,
                hidden: preference?.hidden == true,
                lastActiveAt: lastActive,
                sharedBy: sharedBy(snapshot.projectId, rooms: rooms, connections: connections)
            )
        }
        return rows.sorted { left, right in
            if left.hidden != right.hidden { return !left.hidden }
            if left.working != right.working { return left.working > right.working }
            if left.lastActiveAt != right.lastActiveAt { return left.lastActiveAt > right.lastActiveAt }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    /// The phone a Project arrives through, when it is another person's.
    static func sharedBy(_ projectId: String, rooms: [String: Set<String>], connections: [LinkedComputer]) -> String? {
        let hubs = connections.filter { $0.pairing.isHub && (rooms[projectId] ?? []).contains($0.id) }
        return hubs.map(\.displayName).sorted().first
    }

    static func displayName(_ snapshot: ProjectMeshSnapshot, preference: ProjectPreference?) -> String {
        let custom = preference?.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? snapshot.project.name : custom
    }
}
