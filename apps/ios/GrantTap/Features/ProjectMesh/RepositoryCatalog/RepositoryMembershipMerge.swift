import Foundation

enum RepositoryMembershipMerge {
    static func make(_ members: [RepositoryCatalog.Membership]) -> [RepositoryCatalog.Membership] {
        Dictionary(grouping: members, by: \.projectId).map { _, rows in
            let first = rows[0]
            let tasks = Dictionary(grouping: rows.flatMap(\.tasks), by: \.id).values.compactMap {
                $0.min { rank($0.relation) < rank($1.relation) }
            }.sorted { $0.row.lastActiveAt > $1.row.lastActiveAt }
            return RepositoryCatalog.Membership(projectId: first.projectId, name: first.name,
                primary: rows.contains(where: \.primary), bound: rows.contains(where: \.bound),
                mapped: rows.contains(where: \.mapped), computers: Set(rows.flatMap(\.computers)).sorted(), tasks: tasks,
                observed: rows.contains(where: \.observed))
        }.sorted { $0.projectId < $1.projectId }
    }

    private static func rank(_ relation: RepositoryCatalog.TaskRelation) -> Int {
        switch relation {
        case .current: return 0
        case .multiple: return 1
        case .lastObserved: return 2
        case .previous: return 3
        case .unassigned: return 4
        }
    }
}
