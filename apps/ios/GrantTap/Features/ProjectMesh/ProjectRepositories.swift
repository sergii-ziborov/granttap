import SwiftUI

/// The repositories a Project reaches: its own, the ones its integration map
/// names as the other side, and any a computer has bound to it besides.
///
/// A Project is not one repository. The app's repository has a runtime on
/// the other side of its protocol and a site on the other side of its
/// release, and the map in WEAVATRIX.md says so; a task in one is usually a
/// task in the other. This is that map as a list: where each repository
/// lives, what runs in it, and which Project on this phone is it.
struct ProjectRepositoryRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case own
        case peer(via: String, relation: String, through: String?)
        case seen
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
    static func rows(snapshot: ProjectMeshSnapshot, projects: [ProjectMeshSnapshot]) -> [ProjectRepositoryRow] {
        let bindings = snapshot.bindings ?? []
        let own = snapshot.project.canonicalRepositoryId
        var rows: [ProjectRepositoryRow] = [row(
            id: own, name: ProjectOtherSide.displayName(of: own, in: snapshot), kind: .own,
            repositoryIds: [own], snapshot: snapshot, projects: projects, excluding: snapshot.projectId
        )]
        var covered: Set<String> = [own]

        // The other side of each edge in the map, once per peer and relation.
        var seenPeers = Set<String>()
        let peers = (snapshot.peers ?? []).sorted { $0.peer == $1.peer ? $0.relation < $1.relation : $0.peer < $1.peer }
        for peer in peers {
            let key = "\(peer.peer.lowercased())\u{1f}\(peer.via)\u{1f}\(peer.relation)"
            guard seenPeers.insert(key).inserted else { continue }
            let wanted = peer.peer.trimmingCharacters(in: .whitespaces).lowercased()
            let matching = bindings.filter { ProjectOtherSide.repositoryNames($0).contains(wanted) }.map(\.repositoryId)
            covered.formUnion(matching)
            rows.append(row(
                id: "peer\u{1f}\(key)", name: peer.peer,
                kind: .peer(via: peer.via, relation: peer.relation, through: peer.through),
                repositoryIds: Set(matching), snapshot: snapshot, projects: projects,
                excluding: snapshot.projectId, peerName: wanted
            ))
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
            rows.append(row(
                id: repositoryId, name: ProjectOtherSide.displayName(of: repositoryId, in: snapshot), kind: .seen,
                repositoryIds: [repositoryId], snapshot: snapshot, projects: projects, excluding: snapshot.projectId
            ))
        }
        return rows
    }

    private static func row(
        id: String, name: String, kind: ProjectRepositoryRow.Kind, repositoryIds: Set<String>,
        snapshot: ProjectMeshSnapshot, projects: [ProjectMeshSnapshot], excluding projectId: String,
        peerName: String? = nil
    ) -> ProjectRepositoryRow {
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
            guard other.projectId != projectId else { return false }
            if repositoryIds.contains(other.project.canonicalRepositoryId) { return true }
            guard let peerName else { return false }
            return other.project.name.lowercased() == peerName
                || repositoryLeaf(other.project.canonicalRepositoryId) == peerName
        }
        return ProjectRepositoryRow(
            id: id, name: name, kind: kind, computers: computers,
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
        if let phrase = row.relationPhrase { parts.append(phrase) }
        if case .seen = row.kind { parts.append(L("bound here, not in the map")) }
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
            Text(L("Repositories"))
        } footer: {
            if (snapshot.peers ?? []).isEmpty {
                Text(L("A WEAVATRIX.md in the repository names the other side of it — the runtime of a protocol, the site of a release — and each becomes a row here."))
            }
        }
    }

    private func label(_ row: ProjectRepositoryRow, linked: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(row.kind))
                .frame(width: 24)
                .foregroundColor(row.computers.contains { $0.available } || row.kind == .own ? Theme.codex : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).foregroundColor(Theme.ink)
                    if row.kind == .own {
                        Text(L("this Project")).font(.caption2.weight(.semibold)).foregroundColor(Theme.muted)
                    }
                }
                let detail = ProjectRepositories.detail(row)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
                }
                if let linked {
                    Text(String(format: L("Project: %@"), linked)).font(.caption2).foregroundColor(Theme.codex)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(_ kind: ProjectRepositoryRow.Kind) -> String {
        switch kind {
        case .own: return "folder.fill"
        case .peer: return "arrow.left.arrow.right"
        case .seen: return "folder.badge.questionmark"
        }
    }
}
