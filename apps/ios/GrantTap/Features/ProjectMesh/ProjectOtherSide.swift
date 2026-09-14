import Foundation

/// The other side of a Task's repository.
///
/// A Project binds several repositories, and a bound repository's integration
/// map says which of them sit on the far side of its databases, topics, and
/// APIs. Together they answer what a merge never does: is another Task, right
/// now, changing the other half of a contract this Task is changing? Shared
/// with the bridge vector for vector.
enum ProjectOtherSide {
    struct Edge: Equatable {
        let peer: ProjectIntegrationPeer
        /// The repository on the far side.
        let repositoryId: String
    }

    struct Row: Equatable, Identifiable {
        let taskId: String
        let title: String
        var ownerSessionId: String?
        /// The repository that Task is working in.
        let repositoryId: String
        let via: String
        let relation: String
        var through: String?
        /// The repository whose map states the edge.
        let statedBy: String
        var id: String { "\(taskId)\u{1f}\(statedBy)\u{1f}\(repositoryId)\u{1f}\(via)\u{1f}\(relation)\u{1f}\(through ?? "")" }
    }

    /// The names a repository answers to on a map: what its checkout is called.
    static func repositoryNames(_ binding: ProjectBindingSummary) -> Set<String> {
        var names = Set<String>()
        func add(_ value: String?) {
            let name = (value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if !name.isEmpty { names.insert(name) }
        }
        add(binding.displayName)
        add(binding.localPathHint.map { ($0 as NSString).lastPathComponent })
        var last = binding.repositoryId
        while last.hasSuffix("/") { last.removeLast() }
        add(last.split(separator: "/").last.map { segment in
            let name = String(segment)
            return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
        })
        return names
    }

    private static func repositoryIds(named name: String, in bindings: [ProjectBindingSummary]) -> [String] {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        return bindings.filter { repositoryNames($0).contains(wanted) }
            .map(\.repositoryId).filter { seen.insert($0).inserted }
    }

    /// Repositories on the far side of `repositoryId`, whichever side stated the edge.
    static func otherSides(of repositoryId: String, in snapshot: ProjectMeshSnapshot) -> [Edge] {
        let bindings = snapshot.bindings ?? []
        let mine = Set(bindings.filter { $0.repositoryId == repositoryId }.flatMap { repositoryNames($0) })
        var edges: [Edge] = []
        for peer in snapshot.peers ?? [] {
            if peer.repositoryId == repositoryId {
                for id in repositoryIds(named: peer.peer, in: bindings) where id != repositoryId {
                    edges.append(Edge(peer: peer, repositoryId: id))
                }
            } else if mine.contains(peer.peer.trimmingCharacters(in: .whitespaces).lowercased()) {
                edges.append(Edge(peer: peer, repositoryId: peer.repositoryId))
            }
        }
        return edges
    }

    /// The repository an execution runs in, when the snapshot can tell.
    static func repository(of execution: ExecutionSessionLink, in snapshot: ProjectMeshSnapshot) -> String? {
        if let repositoryId = execution.repositoryId { return repositoryId }
        guard let root = snapshot.project.repositoryRoot else { return nil }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return execution.workspace == root || execution.workspace.hasPrefix(prefix)
            ? snapshot.project.canonicalRepositoryId : nil
    }

    /// Other Tasks working, right now, on the far side of this Task's repositories.
    static func rows(in snapshot: ProjectMeshSnapshot, taskId: String) -> [Row] {
        let live = snapshot.executions.filter { $0.endedAt == nil }
        var mine: [String] = []
        for execution in live where execution.taskId == taskId {
            if let repository = repository(of: execution, in: snapshot), !mine.contains(repository) {
                mine.append(repository)
            }
        }
        var rows: [Row] = []
        var seen = Set<String>()
        for repositoryId in mine {
            for edge in otherSides(of: repositoryId, in: snapshot) {
                for execution in live where execution.taskId != taskId
                    && repository(of: execution, in: snapshot) == edge.repositoryId {
                    guard let task = snapshot.tasks.first(where: { $0.taskId == execution.taskId }) else { continue }
                    let row = Row(
                        taskId: task.taskId, title: task.title, ownerSessionId: task.ownerSessionId,
                        repositoryId: edge.repositoryId, via: edge.peer.via, relation: edge.peer.relation,
                        through: edge.peer.through, statedBy: edge.peer.repositoryId
                    )
                    if seen.insert(row.id).inserted { rows.append(row) }
                }
            }
        }
        return Array(rows.prefix(32))
    }

    /// The short name a repository is shown under.
    static func displayName(of repositoryId: String, in snapshot: ProjectMeshSnapshot) -> String {
        if let binding = (snapshot.bindings ?? []).first(where: { $0.repositoryId == repositoryId }),
           !binding.displayName.isEmpty {
            return binding.displayName
        }
        var last = repositoryId
        while last.hasSuffix("/") { last.removeLast() }
        let name = last.split(separator: "/").last.map(String.init) ?? repositoryId
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }

    /// The edge as the map states it, in words.
    static func phrase(relation: String, through: String?) -> String {
        switch relation {
        case "produces": return String(format: L("produces %@"), through ?? "")
        case "consumes": return String(format: L("consumes %@"), through ?? "")
        case "shares": return String(format: L("shares %@"), through ?? "")
        case "calls": return L("calls its API")
        case "called_by": return L("is called by it")
        default: return relation
        }
    }

    /// "payments-api produces payment.completed · payment-worker".
    static func describe(_ row: Row, in snapshot: ProjectMeshSnapshot) -> String {
        "\(displayName(of: row.statedBy, in: snapshot)) \(phrase(relation: row.relation, through: row.through)) · \(displayName(of: row.repositoryId, in: snapshot))"
    }
}
