import Foundation

/// What this phone decided about a Project: what to call it, whether to show it.
///
/// A Project keeps the identity reported by the computer. Its default display
/// name follows the canonical repository when known, while this phone keeps a
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
        localProjectIds: Set<String> = [],
        now: Double = Date().timeIntervalSince1970 * 1_000
    ) -> [ProjectListRow] {
        let visibleSnapshots = snapshots.filter {
            !isRedundantEmptyProject($0, among: snapshots, rooms: rooms,
                                     localProjectIds: localProjectIds)
        }
        let rows = visibleSnapshots.map { snapshot -> ProjectListRow in
            let preference = preferences[snapshot.projectId]
            let taskRows = ProjectMeshRecency.rows(
                snapshot.tasks, snapshot: snapshot, sessions: sessions
            )
            let states = taskRows.map(\.state)
            let lastActive = taskRows.first?.lastActiveAt ?? 0
            return ProjectListRow(
                projectId: snapshot.projectId,
                name: displayName(snapshot, preference: preference),
                repositoryLeaf: ProjectRepositories.repositoryLeaf(snapshot.project.canonicalRepositoryId),
                computers: ProjectManagePresentation.endpointIds(snapshot).count,
                openTasks: snapshot.tasks.filter { !["completed", "failed"].contains($0.state) }.count,
                working: states.filter { $0 == "working" }.count,
                needsYou: states.filter { $0 == "needs_user" || $0 == "blocked" }.count,
                members: memberLinks.filter { $0.allowsProject(snapshot.projectId) }.count,
                holdsKey: localProjectIds.contains(snapshot.projectId)
                    || !(rooms[snapshot.projectId] ?? []).isEmpty,
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

    /// Old local and remote identities can coexist after a repository gains or
    /// changes its Git remote. Keep any Project with work; suppress only an
    /// empty twin from the same checkout and authenticated computer.
    static func isRedundantEmptyProject(
        _ snapshot: ProjectMeshSnapshot, among all: [ProjectMeshSnapshot],
        rooms: [String: Set<String>], localProjectIds: Set<String> = []
    ) -> Bool {
        guard snapshot.tasks.isEmpty, snapshot.executions.isEmpty,
              snapshot.claims.isEmpty, snapshot.events.isEmpty else { return false }
        let owners = rooms[snapshot.projectId] ?? []
        let localOwner = localProjectIds.contains(snapshot.projectId)
        guard !owners.isEmpty || localOwner else { return false }
        let root = normalizedRoot(snapshot.project.repositoryRoot)
        return all.contains { other in
            guard other.projectId != snapshot.projectId,
                  !other.tasks.isEmpty || !other.executions.isEmpty,
                  (!owners.isDisjoint(with: rooms[other.projectId] ?? [])
                    || (localOwner && localProjectIds.contains(other.projectId))) else { return false }
            return other.project.canonicalRepositoryId == snapshot.project.canonicalRepositoryId
                || (!root.isEmpty && root == normalizedRoot(other.project.repositoryRoot))
        }
    }

    private static func normalizedRoot(_ root: String?) -> String {
        guard let root else { return "" }
        return root.lowercased().replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// The phone a Project arrives through, when it is another person's.
    static func sharedBy(_ projectId: String, rooms: [String: Set<String>], connections: [LinkedComputer]) -> String? {
        let hubs = connections.filter { $0.pairing.isHub && (rooms[projectId] ?? []).contains($0.id) }
        return hubs.map(\.displayName).sorted().first
    }

    static func displayName(_ snapshot: ProjectMeshSnapshot, preference: ProjectPreference?) -> String {
        let custom = preference?.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        let repository = snapshot.project.canonicalRepositoryId
        if !repository.hasPrefix("local:"), repository.contains("/") {
            let leaf = ProjectRepositories.repositoryLeaf(repository)
            if !leaf.isEmpty { return leaf }
        }
        return snapshot.project.name
    }
}
