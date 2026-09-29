import SwiftUI

/// Repository browsing preserves the original Mesh route for every chat.
struct RepositoryCatalogDetailView: View {
    let repositoryId: String
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }

    private var entry: RepositoryCatalog.Entry? {
        let canonical = RepositoryIdentityIndex.canonical(repositoryId, snapshots: model.repositoryVisibleSnapshots)
        return RepositoryCatalog.make(rows: model.projectListRows, snapshots: model.meshSnapshots,
                                      sessions: model.sessions).first { $0.id == canonical }
    }

    var body: some View {
        List {
            if let entry {
                Section(L("Repository")) {
                    Text(entry.id.hasPrefix("local:") ? String(entry.id.dropFirst(6)) : entry.id)
                        .font(.callout).textSelection(.enabled)
                        .accessibilityIdentifier("repository.identity")
                }
                Section(L("Activity")) {
                    Text(RepositoryActivity.summary(entry))
                        .foregroundStyle(RepositoryActivity.working(entry) > 0 ? Theme.ok : Theme.muted)
                        .accessibilityIdentifier("repository.activity")
                }
                taskSections(entry)
                ForEach(entry.memberships) { member in
                    membershipSection(member)
                }
                RepositoryGitSections(entry: entry, model: model)
            } else {
                Text(L("This repository is no longer in the visible Mesh catalog."))
                    .foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .pageNavigationTitle(entry?.name ?? L("Repository"))
        .task(id: repositoryId) { await model.observeRepositoryDetails(repositoryId: repositoryId) }
        .refreshable {
            for member in entry?.memberships ?? [] {
                await model.refreshProjectInsights(projectId: member.projectId, requestRemote: true)
            }
        }
    }

    @ViewBuilder private func taskSections(_ entry: RepositoryCatalog.Entry) -> some View {
        let references = entry.memberships.flatMap(\.tasks)
        let current = references.filter { $0.relation != .previous }
        let previous = references.filter { $0.relation == .previous }
        if !current.isEmpty {
            Section(L("Tasks")) {
                ForEach(current) { reference in
                    RepositoryCatalogTaskLink(reference: reference, repositoryId: entry.id,
                                              model: model, onOpenSession: onOpenSession)
                }
            }
        }
        if !previous.isEmpty {
            Section(L("Previous executions")) {
                ForEach(previous) { reference in
                    RepositoryCatalogTaskLink(reference: reference, repositoryId: entry.id,
                                              model: model, onOpenSession: onOpenSession)
                }
            }
        }
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
            VStack(alignment: .leading, spacing: 3) {
                ProjectMeshTaskRow(task: row.task, execution: row.execution, currentSession: row.session,
                    presentedState: row.state, lastActiveAt: row.lastActiveAt,
                    repositoryContext: RepositoryCatalogPresentation.relation(reference, repositoryId: repositoryId))
                if let home = reference.presentedProjectId, let name = model.projectDisplayName(id: home) {
                    Text(String(format: L("Mesh: %@"), name)).font(.caption).foregroundStyle(Theme.codex)
                    if home != row.task.projectId, let source = model.projectDisplayName(id: row.task.projectId) {
                        Text(String(format: L("Started in Mesh: %@"), source)).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .accessibilityIdentifier("repository.task.\(row.task.projectId).\(row.task.taskId)")
    }
}
