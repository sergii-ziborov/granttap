import Foundation

/// Presentation groups only. Each Project keeps its own identity and access scope.
enum ProjectSolutionGroups {
    struct Group: Identifiable {
        let id: String
        let rows: [ProjectListRow]
        var title: String { rows.map(\.name).sorted().first ?? L("Solution") }
    }

    static func make(
        rows: [ProjectListRow], snapshots: [String: ProjectMeshSnapshot]
    ) -> (solutions: [Group], linked: [Group], ungrouped: [ProjectListRow]) {
        var parent = Dictionary(uniqueKeysWithValues: rows.map { ($0.projectId, $0.projectId) })
        var byRepository: [String: [ProjectListRow]] = [:]
        for row in rows {
            guard let snapshot = snapshots[row.projectId] else { continue }
            for repository in repositoryIDs(snapshot) {
                byRepository[repository, default: []].append(row)
            }
        }
        func root(_ id: String) -> String {
            var current = id
            while let next = parent[current], next != current { current = next }
            return current
        }
        for snapshot in snapshots.values {
            for pair in verifiedPairs(snapshot) {
                for left in byRepository[pair.0] ?? [] {
                    for right in byRepository[pair.1] ?? [] {
                        let leftRoot = root(left.projectId)
                        let rightRoot = root(right.projectId)
                        if leftRoot != rightRoot { parent[rightRoot] = leftRoot }
                    }
                }
            }
        }
        // Bindings and Task executions report repository membership even before
        // Weavatrix verifies a dependency. Keep these groups distinct from Solutions.
        var repositoryLinked = Set<String>()
        for repository in byRepository.keys.sorted() {
            let members = byRepository[repository] ?? []
            guard let first = members.first else { continue }
            for peer in members.dropFirst() {
                let leftRoot = root(first.projectId)
                let rightRoot = root(peer.projectId)
                if leftRoot != rightRoot {
                    parent[rightRoot] = leftRoot
                    repositoryLinked.insert(first.projectId)
                    repositoryLinked.insert(peer.projectId)
                }
            }
        }
        let groups = Dictionary(grouping: rows) { root($0.projectId) }
        func ordered(_ members: [[ProjectListRow]]) -> [Group] {
            members.map { members in
            Group(id: members.map(\.projectId).sorted().first ?? "", rows: members)
            }.sorted { left, right in
                let leftActive = left.rows.map(\.lastActiveAt).max() ?? 0
                let rightActive = right.rows.map(\.lastActiveAt).max() ?? 0
                return leftActive == rightActive ? left.id < right.id : leftActive > rightActive
            }
        }
        let connected = groups.values.filter { $0.count > 1 }
        let solutions = ordered(connected.filter { $0.allSatisfy { !repositoryLinked.contains($0.projectId) } })
        let linked = ordered(connected.filter { $0.contains { repositoryLinked.contains($0.projectId) } })
        return (solutions, linked, rows.filter { groups[root($0.projectId)]?.count == 1 })
    }

    private static func repositoryIDs(_ snapshot: ProjectMeshSnapshot) -> Set<String> {
        // A non-Git parent workspace collects observations from unrelated
        // Tasks. It cannot bridge their repository Meshes transitively.
        guard !ProjectTaskRepositoryGroups.isWorkspace(snapshot) else { return [] }
        let taskIDs = Set(snapshot.tasks.filter { $0.projectId == snapshot.projectId }.map(\.taskId))
        let bindings = (snapshot.bindings ?? []).filter { $0.projectId == snapshot.projectId }
        let executions = snapshot.executions.filter { taskIDs.contains($0.taskId) }
        let repositories = [snapshot.project.canonicalRepositoryId]
            + bindings.map(\.repositoryId) + executions.compactMap(\.repositoryId)
        return Set(repositories.filter { !$0.isEmpty })
    }

    /// Ownership is structural. A non-ownership relation needs positive evidence
    /// between nodes owned by two distinct repositories before we group them.
    static func verifiedPairs(_ snapshot: ProjectMeshSnapshot) -> [(String, String)] {
        guard let backbone = snapshot.backbone else { return [] }
        let nodeIDs = Set(backbone.nodes.map(\.identity))
        let repositories = Set(backbone.nodes.filter { $0.kind == "repository" }.map(\.identity))
        var children: [String: [String]] = [:]
        var pairs = Set<String>()
        var result: [(String, String)] = []
        for edge in backbone.relations where edge.relation == "owns" && edge.evidenceCount > 0 {
            guard nodeIDs.contains(edge.source), nodeIDs.contains(edge.target) else { continue }
            children[edge.source, default: []].append(edge.target)
            if repositories.contains(edge.source), repositories.contains(edge.target),
               edge.source != edge.target {
                let pair = [edge.source, edge.target].sorted()
                if pairs.insert(pair.joined(separator: "\u{1f}")).inserted {
                    result.append((pair[0], pair[1]))
                }
            }
        }
        var owners: [String: Set<String>] = [:]
        for repository in repositories {
            var visited: Set<String> = [repository]
            var pending = [repository]
            while let node = pending.popLast() {
                owners[node, default: []].insert(repository)
                for child in children[node] ?? [] {
                    guard !repositories.contains(child), visited.insert(child).inserted else { continue }
                    pending.append(child)
                }
            }
        }
        for edge in backbone.relations where edge.relation != "owns" && edge.evidenceCount > 0 {
            guard let sourceOwners = owners[edge.source], sourceOwners.count == 1,
                  let targetOwners = owners[edge.target], targetOwners.count == 1,
                  let source = sourceOwners.first, let target = targetOwners.first,
                  source != target else { continue }
            let pair = [source, target].sorted()
            if pairs.insert(pair.joined(separator: "\u{1f}")).inserted {
                result.append((pair[0], pair[1]))
            }
        }
        return result
    }
}
