import SwiftUI

/// Repositories reached through verified backbone relations, plus every
/// repository a computer has bound to this Project.
struct ProjectRepositoryRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case own
        case workspace
        case workspaceObservation
        case peer(via: String, relation: String, through: String?)
        case seen
        case relatedByBinding
    }

    let id: String
    let name: String
    let kind: Kind
    /// Computers that have this repository bound, available ones first.
    let computers: [(endpointId: String, available: Bool)]
    let openTasks: Int
    let branches: [String]
    /// Another Project on this phone whose repository this is, if any.
    let projectId: String?
    var repositoryIds: [String] = []

    static func == (lhs: ProjectRepositoryRow, rhs: ProjectRepositoryRow) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.kind == rhs.kind && lhs.openTasks == rhs.openTasks
            && lhs.branches == rhs.branches && lhs.projectId == rhs.projectId && lhs.repositoryIds == rhs.repositoryIds
            && lhs.computers.map(\.endpointId) == rhs.computers.map(\.endpointId)
            && lhs.computers.map(\.available) == rhs.computers.map(\.available)
    }

    var relationPhrase: String? {
        if case .peer(_, let relation, let through) = kind {
            return ProjectOtherSide.phrase(relation: relation, through: through)
        }
        return nil
    }
}

enum ProjectRepositories {
    private struct RowInput {
        let id: String
        let name: String
        let kind: ProjectRepositoryRow.Kind
        let repositoryIds: Set<String>
    }

    static func rows(snapshot: ProjectMeshSnapshot, projects: [ProjectMeshSnapshot]) -> [ProjectRepositoryRow] {
        let bindings = snapshot.bindings ?? []
        let own = snapshot.project.canonicalRepositoryId
        let workspace = ProjectTaskRepositoryGroups.isWorkspace(snapshot)
        let ownInput = RowInput(
            id: own, name: ProjectOtherSide.displayName(of: own, in: snapshot),
            kind: workspace ? .workspace : .own, repositoryIds: [own]
        )
        var rows: [ProjectRepositoryRow] = [row(
            ownInput, snapshot: snapshot, projects: projects, excluding: snapshot.projectId
        )]
        var covered: Set<String> = [own]

        let topology = ProjectGraphTopology.repositoryMap(snapshot)
        var seenPeers = Set<String>()
        let verifiedEdges = snapshot.backbone?.relations.isEmpty == false ? topology.edges : []
        for edge in verifiedEdges {
            let other: String
            if edge.source == own { other = edge.target }
            else if edge.target == own { other = edge.source }
            else { continue }
            guard seenPeers.insert(edge.id).inserted else { continue }
            covered.insert(other)
            let input = RowInput(
                id: "backbone\u{1f}\(edge.id)",
                name: topology.names[other] ?? ProjectOtherSide.displayName(of: other, in: snapshot),
                kind: .peer(via: "engine", relation: edge.relation, through: edge.through),
                repositoryIds: [other]
            )
            rows.append(row(input, snapshot: snapshot, projects: projects, excluding: snapshot.projectId))
        }

        // Compatibility peers remain visible when the verified backbone does
        // not yet connect the Project's repositories.
        let peers = verifiedEdges.isEmpty ? (snapshot.peers ?? []).sorted {
            $0.peer == $1.peer ? $0.relation < $1.relation : $0.peer < $1.peer
        } : []
        for peer in peers {
            let key = "\(peer.peer.lowercased())\u{1f}\(peer.via)\u{1f}\(peer.relation)"
            guard seenPeers.insert(key).inserted else { continue }
            let wanted = peer.peer.trimmingCharacters(in: .whitespaces).lowercased()
            let matching = bindings.filter { ProjectOtherSide.repositoryNames($0).contains(wanted) }.map(\.repositoryId)
            covered.formUnion(matching)
            let input = RowInput(
                id: "peer\u{1f}\(key)", name: peer.peer,
                kind: .peer(via: peer.via, relation: peer.relation, through: peer.through),
                repositoryIds: Set(matching)
            )
            rows.append(row(input, snapshot: snapshot, projects: projects, excluding: snapshot.projectId))
        }

        // Anything else a computer bound or ran in for this Project.
        var others: [String] = []
        for binding in bindings where !covered.contains(binding.repositoryId) {
            if !others.contains(binding.repositoryId) { others.append(binding.repositoryId) }
        }
        for execution in snapshot.executions {
            if let repositoryId = execution.repositoryId, !covered.contains(repositoryId), !others.contains(repositoryId) {
                others.append(repositoryId)
            }
        }
        for repositoryId in others.sorted() {
            let input = RowInput(
                id: repositoryId, name: ProjectOtherSide.displayName(of: repositoryId, in: snapshot),
                kind: workspace ? .workspaceObservation : .seen,
                repositoryIds: [repositoryId]
            )
            rows.append(row(input, snapshot: snapshot, projects: projects, excluding: snapshot.projectId))
        }
        // A binding reported by a different Project also matters when viewed
        // from the repository's own Project. This is navigation evidence, not
        // an admission or a verified Weavatrix dependency.
        for other in projects.sorted(by: { $0.projectId < $1.projectId }) where other.projectId != snapshot.projectId {
            guard !ProjectTaskRepositoryGroups.isWorkspace(other) else { continue }
            let otherRepository = other.project.canonicalRepositoryId
            guard otherRepository != own, !covered.contains(otherRepository) else { continue }
            let boundHere = (other.bindings ?? []).contains {
                $0.projectId == other.projectId && $0.repositoryId == own
            } || other.executions.contains { $0.repositoryId == own }
            guard boundHere else { continue }
            covered.insert(otherRepository)
            let input = RowInput(
                id: "related\u{1f}\(other.projectId)",
                name: ProjectOtherSide.displayName(of: otherRepository, in: other),
                kind: .relatedByBinding, repositoryIds: [otherRepository]
            )
            rows.append(row(input, snapshot: snapshot, projects: projects, excluding: snapshot.projectId))
        }
        return rows
    }

    private static func row(
        _ input: RowInput, snapshot: ProjectMeshSnapshot,
        projects: [ProjectMeshSnapshot], excluding projectId: String
    ) -> ProjectRepositoryRow {
        let repositoryIds = input.repositoryIds
        let bindings = (snapshot.bindings ?? []).filter { repositoryIds.contains($0.repositoryId) }
        var computers: [(endpointId: String, available: Bool)] = []
        for binding in bindings.sorted(by: { $0.available && !$1.available || ($0.available == $1.available && $0.endpointId < $1.endpointId) }) {
            if let index = computers.firstIndex(where: { $0.endpointId == binding.endpointId }) {
                if binding.available { computers[index].available = true }
            } else {
                computers.append((binding.endpointId, binding.available))
            }
        }
        let open = snapshot.executions.filter { $0.endedAt == nil && $0.repositoryId.map(repositoryIds.contains) == true }
        let branches = Array(Set(open.compactMap { $0.branch?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        let project = projects.first { other in
            if input.kind == .own || input.kind == .workspace { return false }
            guard other.projectId != projectId else { return false }
            return repositoryIds.contains(other.project.canonicalRepositoryId)
        }
        return ProjectRepositoryRow(
            id: input.id, name: input.name, kind: input.kind, computers: computers,
            openTasks: Set(open.map(\.taskId)).count, branches: branches, projectId: project?.projectId,
            repositoryIds: repositoryIds.sorted()
        )
    }

    static func repositoryLeaf(_ repositoryId: String) -> String {
        var last = repositoryId
        while last.hasSuffix("/") { last.removeLast() }
        let leaf = last.split(separator: "/").last.map(String.init) ?? last
        return (leaf.hasSuffix(".git") ? String(leaf.dropLast(4)) : leaf).lowercased()
    }

    /// "on Mac.lan · 2 open tasks · main, feat/x", the parts that are there.
    static func detail(_ row: ProjectRepositoryRow) -> String {
        var parts: [String] = []
        if row.kind == .workspace { parts.append(L("Workspace root; no Git repository confirmed here")) }
        if row.kind == .workspaceObservation { parts.append(L("Observed in workspace Tasks")) }
        if let phrase = row.relationPhrase { parts.append(phrase) }
        if case .seen = row.kind { parts.append(L("bound here, not in the map")) }
        if case .relatedByBinding = row.kind {
            parts.append(L("This repository is linked to another Mesh; no graph dependency has been verified."))
        }
        if !row.computers.isEmpty {
            let names = row.computers.map { $0.available ? $0.endpointId : "\($0.endpointId) (\(L("offline")))" }
            parts.append(String(format: L("on %@"), names.joined(separator: ", ")))
        } else if case .peer = row.kind {
            parts.append(L("not bound on any computer"))
        }
        if row.openTasks > 0 { parts.append(LPlural(row.openTasks, one: "%d open task", many: "%d open tasks")) }
        if !row.branches.isEmpty { parts.append(row.branches.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
