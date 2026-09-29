import SwiftUI

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
                if row.repositoryIds.count > 1 {
                    label(row, linked: nil)
                    ForEach(row.repositoryIds, id: \.self) { repositoryId in
                        NavigationLink(repositoryId.hasPrefix("local:") ? row.name : repositoryId) {
                            RepositoryCatalogDetailView(repositoryId: repositoryId, model: model, onOpenSession: onOpenSession)
                        }
                        .accessibilityIdentifier("project.repository.\(repositoryId)")
                    }
                } else if let repositoryId = row.repositoryIds.first {
                    NavigationLink {
                        RepositoryCatalogDetailView(repositoryId: repositoryId, model: model, onOpenSession: onOpenSession)
                    } label: {
                        label(row, linked: nil)
                    }
                    .accessibilityIdentifier("project.repository.\(row.id)")
                } else if let projectId = row.projectId, let target = model.meshSnapshots[projectId] {
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
                ForEach(row.repositoryIds.filter { !$0.hasPrefix("local:") }, id: \.self) { repositoryId in
                    Text(repositoryId).font(.caption).foregroundColor(Theme.codex)
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
