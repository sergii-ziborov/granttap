import Foundation

/// A repository index over visible Mesh scopes, without changing their grants.
enum RepositoryCatalog {
    enum TaskRelation: Equatable { case current, lastObserved, previous, multiple, unassigned }

    struct TaskReference: Identifiable {
        let row: ProjectMeshRecency.Row
        let relation: TaskRelation
        var presentedProjectId: String? = nil
        var id: String { row.task.taskId }
    }

    struct Membership: Identifiable {
        let projectId: String
        let name: String
        let primary: Bool
        let bound: Bool
        let mapped: Bool
        let computers: [String]
        let tasks: [TaskReference]
        var observed = false
        var id: String { projectId }
    }

    struct Entry: Identifiable {
        let id: String
        let name: String
        let isGit: Bool
        let memberships: [Membership]
    }

    private struct Contribution {
        let repositoryId: String
        let name: String
        let isGit: Bool
        let membership: Membership
    }

    static func make(
        rows: [ProjectListRow], snapshots: [String: ProjectMeshSnapshot], sessions: [SessionInfo]
    ) -> [Entry] {
        let visible = rows.filter { !$0.hidden }.compactMap { snapshots[$0.projectId] }
        let placements = Dictionary(uniqueKeysWithValues: MeshTaskPlacement.make(snapshots: visible, sessions: sessions)
            .map { ($0.row.task.taskId, $0.projectId) })
        let contributions = rows.filter { !$0.hidden }.sorted { $0.projectId < $1.projectId }.flatMap { row in
            snapshots[row.projectId].map { Self.contributions(snapshot: $0, name: row.name, sessions: sessions,
                snapshots: visible, placements: placements) } ?? []
        }
        return Dictionary(grouping: contributions, by: \.repositoryId).map { id, matches in
            Entry(id: id, name: matches[0].name, isGit: matches.contains(where: \.isGit),
                  memberships: RepositoryMembershipMerge.make(matches.map(\.membership)))
        }.sorted { left, right in
            if RepositoryActivity.working(left) != RepositoryActivity.working(right) {
                return RepositoryActivity.working(left) > RepositoryActivity.working(right)
            }
            let order = left.name.localizedCaseInsensitiveCompare(right.name)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }

    private static func contributions(
        snapshot: ProjectMeshSnapshot, name: String, sessions: [SessionInfo],
        snapshots: [ProjectMeshSnapshot], placements: [String: String]
    ) -> [Contribution] {
        let tasks = snapshot.tasks.filter { $0.projectId == snapshot.projectId }
        let taskIds = Set(tasks.map(\.taskId))
        let executions = snapshot.executions.filter { taskIds.contains($0.taskId) }
        let bindings = (snapshot.bindings ?? []).filter { $0.projectId == snapshot.projectId }
        let rawMapped = Set((snapshot.backbone?.nodes ?? []).filter { $0.kind == "repository" }.map(\.identity))
        let rawIds = Set([snapshot.project.canonicalRepositoryId] + bindings.map(\.repositoryId)
            + executions.compactMap(\.repositoryId)).union(rawMapped).filter { !$0.isEmpty }
        let aliases = Dictionary(uniqueKeysWithValues: rawIds.map {
            ($0, RepositoryIdentityIndex.canonical($0, snapshots: snapshots))
        })
        let canonical: (String) -> String = { aliases[$0] ?? $0 }
        let mapped = Set(rawMapped.map(canonical))
        let ids = Set(rawIds.map(canonical))
        let confirmed = ProjectTaskRepositoryGroups.confirmedRepositories(snapshot)
        let rows = ProjectMeshRecency.rows(tasks, snapshot: snapshot, sessions: sessions)
        let assignments = ProjectTaskRepositoryGroups.assignments(snapshot)
        let history = Dictionary(grouping: executions, by: \.taskId)
        return ids.sorted().map { repository in
            let bound = bindings.filter { canonical($0.repositoryId) == repository }
            let observed = executions.filter { $0.repositoryId.map(canonical) == repository }
            let refs = rows.compactMap { row -> TaskReference? in
                let rawAssignment = assignments[row.task.taskId] ?? .init(repositoryIds: [], isCurrent: false)
                let assignment = ProjectTaskRepositoryGroups.Assignment(
                    repositoryIds: Array(Set(rawAssignment.repositoryIds.map(canonical))), isCurrent: rawAssignment.isCurrent)
                let repositories = (history[row.task.taskId] ?? []).compactMap(\.repositoryId).map(canonical)
                guard let relation = relation(repository: repository, assignment: assignment, history: repositories,
                    primary: repository == canonical(snapshot.project.canonicalRepositoryId)) else { return nil }
                return TaskReference(row: row, relation: relation, presentedProjectId: placements[row.task.taskId])
            }
            return Contribution(repositoryId: repository,
                name: ProjectOtherSide.displayName(of: repository, in: snapshot),
                isGit: confirmed.map(canonical).contains(repository) || (mapped.contains(repository) && !repository.hasPrefix("local:")),
                membership: Membership(
                    projectId: snapshot.projectId, name: name,
                    primary: repository == canonical(snapshot.project.canonicalRepositoryId),
                    bound: !bound.isEmpty, mapped: mapped.contains(repository),
                    computers: Set(bound.map(\.endpointId) + observed.map(\.computerId)).sorted(), tasks: refs,
                    observed: !observed.isEmpty))
        }
    }

    private static func relation(
        repository: String, assignment: ProjectTaskRepositoryGroups.Assignment,
        history: [String], primary: Bool
    ) -> TaskRelation? {
        if assignment.repositoryIds.contains(repository) {
            if assignment.repositoryIds.count > 1 { return .multiple }
            return assignment.isCurrent ? .current : .lastObserved
        }
        if history.contains(repository) { return assignment.repositoryIds.isEmpty ? .unassigned : .previous }
        return primary && assignment.repositoryIds.isEmpty ? .unassigned : nil
    }
}
