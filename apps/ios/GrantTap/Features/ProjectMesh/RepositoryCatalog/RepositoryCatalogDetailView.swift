import SwiftUI

/// Repository browsing preserves the original Mesh route for every chat.
struct RepositoryCatalogDetailView: View {
    let repositoryId: String
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }

    private var entry: RepositoryCatalog.Entry? {
        RepositoryCatalog.make(rows: model.projectListRows, snapshots: model.meshSnapshots,
                               sessions: model.sessions).first { $0.id == repositoryId }
    }

    var body: some View {
        List {
            if let entry {
                Section(L("Repository")) {
                    Text(RepositoryCatalogPresentation.identity(entry))
                        .font(.callout).textSelection(.enabled)
                        .accessibilityIdentifier("repository.identity")
                }
                ForEach(entry.memberships) { member in
                    membershipSection(member)
                }
            } else {
                Text(L("This repository is no longer in the visible Mesh catalog."))
                    .foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .pageNavigationTitle(entry?.name ?? L("Repository"))
    }

    private func membershipSection(_ member: RepositoryCatalog.Membership) -> some View {
        Section {
            if let snapshot = model.meshSnapshots[member.projectId] {
                NavigationLink {
                    ProjectMeshView(snapshot: snapshot, model: model, onOpenSession: onOpenSession)
                } label: {
                    Label(String(format: L("Mesh: %@"), member.name), systemImage: "point.3.connected.trianglepath.dotted")
                }
                .accessibilityIdentifier("repository.mesh.\(member.projectId)")
            }
            if !member.computers.isEmpty {
                Text(member.computers.map {
                    ProjectHealthDiagnostics.computerName($0, connections: model.connectionRegistry.connections)
                }.joined(separator: ", "))
                .font(.caption).foregroundStyle(Theme.muted)
            }
            if member.tasks.isEmpty {
                Text(L("No chat execution has reported this repository in this Mesh."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(member.tasks) { reference in
                RepositoryCatalogTaskLink(reference: reference, repositoryId: repositoryId,
                                          model: model, onOpenSession: onOpenSession)
            }
        } header: {
            Text(member.name)
        } footer: {
            Text(RepositoryCatalogPresentation.membership(member))
        }
    }
}

private struct RepositoryCatalogTaskLink: View {
    let reference: RepositoryCatalog.TaskReference
    let repositoryId: String
    @ObservedObject var model: AppModel
    let onOpenSession: (SessionInfo) -> Void

    var body: some View {
        let row = reference.row
        NavigationLink {
            TaskRouteView(route: .init(projectId: row.task.projectId, taskId: row.task.taskId),
                          model: model, onOpenSession: onOpenSession, presentedAsSheet: false)
        } label: {
            ProjectMeshTaskRow(task: row.task, execution: row.execution, currentSession: row.session,
                presentedState: row.state, lastActiveAt: row.lastActiveAt,
                repositoryContext: RepositoryCatalogPresentation.relation(reference, repositoryId: repositoryId))
        }
        .accessibilityIdentifier("repository.task.\(row.task.projectId).\(row.task.taskId)")
    }
}
