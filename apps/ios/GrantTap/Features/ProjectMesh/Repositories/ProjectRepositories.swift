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

    static func == (lhs: ProjectRepositoryRow, rhs: ProjectRepositoryRow) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.kind == rhs.kind && lhs.openTasks == rhs.openTasks
            && lhs.branches == rhs.branches && lhs.projectId == rhs.projectId
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
            openTasks: Set(open.map(\.taskId)).count, branches: branches, projectId: project?.projectId
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

/// The Repositories section of a Project screen: a row per repository, with
/// a way through to the Project that is that repository when there is one.
struct ProjectRepositoriesSection: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }

    var rows: [ProjectRepositoryRow] {
        ProjectRepositories.rows(snapshot: snapshot, projects: Array(model.meshSnapshots.values))
    }

    var body: some View {
        let rows = rows
        Section {
            ForEach(rows) { row in
                if let projectId = row.projectId, let target = model.meshSnapshots[projectId] {
                    NavigationLink {
                        ProjectMeshView(snapshot: target, model: model, onOpenSession: onOpenSession)
                    } label: {
                        label(row, linked: model.projectDisplayName(target))
                    }
                    .accessibilityIdentifier("project.repository.\(row.id)")
                } else {
                    label(row, linked: nil)
                        .accessibilityIdentifier("project.repository.\(row.id)")
                }
            }
        } header: {
            Text(ProjectTaskRepositoryGroups.isWorkspace(snapshot) ? L("Task repositories") : L("Repositories"))
        } footer: {
            if ProjectTaskRepositoryGroups.isWorkspace(snapshot) {
                Text(L("Tasks are grouped automatically by their execution repositories."))
            } else if (snapshot.peers ?? []).isEmpty {
                Text(L("Only Engine relations are verified architecture. Repository bindings can link Mesh views without merging access or proving a dependency."))
            }
        }
    }

    private func label(_ row: ProjectRepositoryRow, linked: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(row.kind))
                .frame(width: 24)
                .foregroundColor(row.computers.contains { $0.available }
                    || row.kind == .own || row.kind == .workspace ? Theme.codex : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).foregroundColor(Theme.ink)
                    if row.kind == .own {
                        Text(L("this Mesh")).font(.caption2.weight(.semibold)).foregroundColor(Theme.muted)
                    } else if row.kind == .workspace {
                        Text(L("workspace")).font(.caption2.weight(.semibold)).foregroundColor(Theme.muted)
                    }
                }
                let detail = ProjectRepositories.detail(row)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
                }
                if let linked {
                    Text(String(format: L("Mesh scope: %@"), linked)).font(.caption2).foregroundColor(Theme.codex)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(_ kind: ProjectRepositoryRow.Kind) -> String {
        switch kind {
        case .own: return "folder.fill"
        case .workspace: return "square.stack"
        case .workspaceObservation: return "folder"
        case .peer: return "arrow.left.arrow.right"
        case .seen: return "folder.badge.questionmark"
        case .relatedByBinding: return "arrow.left.arrow.right"
        }
    }
}
