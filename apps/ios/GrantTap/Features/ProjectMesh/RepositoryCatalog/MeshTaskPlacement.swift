import Foundation

/// Repository presentation may change; the Task's durable access scope stays intact.
enum MeshTaskPlacement {
    struct Placement {
        let row: ProjectMeshRecency.Row
        let sourceProjectId: String
        let projectId: String
    }

    static func make(snapshots: [ProjectMeshSnapshot], sessions: [SessionInfo]) -> [Placement] {
        let homes = Dictionary(grouping: snapshots) {
            RepositoryIdentityIndex.canonical($0.project.canonicalRepositoryId, snapshots: snapshots)
        }
        return snapshots.flatMap { snapshot in
            let assignments = ProjectTaskRepositoryGroups.assignments(snapshot)
            return ProjectMeshRecency.rows(snapshot.tasks.filter { $0.projectId == snapshot.projectId },
                snapshot: snapshot, sessions: sessions).map { row in
                var home = snapshot.projectId
                if let assignment = assignments[row.task.taskId], assignment.isCurrent {
                    let identities = Set(assignment.repositoryIds.map {
                        RepositoryIdentityIndex.canonical($0, snapshots: snapshots)
                    })
                    let source = RepositoryIdentityIndex.canonical(snapshot.project.canonicalRepositoryId, snapshots: snapshots)
                    if identities.count == 1, let canonical = identities.first {
                        let candidates = homes[canonical] ?? []
                        if source != canonical, candidates.count == 1 { home = candidates[0].projectId }
                    }
                }
                return Placement(row: row, sourceProjectId: snapshot.projectId, projectId: home)
            }
        }.sorted {
            if $0.row.lastActiveAt != $1.row.lastActiveAt { return $0.row.lastActiveAt > $1.row.lastActiveAt }
            return $0.row.task.taskId < $1.row.task.taskId
        }
    }
}
