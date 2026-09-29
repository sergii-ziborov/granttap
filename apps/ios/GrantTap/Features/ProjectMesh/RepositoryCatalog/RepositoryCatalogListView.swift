import SwiftUI

struct RepositoryCatalogListView: View {
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }

    var body: some View {
        let entries = RepositoryCatalog.make(rows: model.projectListRows,
            snapshots: model.meshSnapshots, sessions: model.sessions)
        List {
            if entries.isEmpty {
                Text(L("No repositories reported by visible Mesh spaces yet."))
                    .foregroundStyle(Theme.muted)
            }
            repositorySection(entries.filter(\.isGit), title: L("Repositories"))
            repositorySection(entries.filter { !$0.isGit }, title: L("Workspaces without confirmed Git"))
            if !entries.isEmpty {
                Section {
                    Text(L("Open a repository to see its Mesh scopes and chats. Each Mesh keeps its own permissions."))
                        .font(.caption).foregroundStyle(Theme.muted)
                    if model.meshSnapshots.values.contains(where: { $0.incomplete == true }) {
                        Text(L("Some Mesh data is incomplete; more repositories may arrive from the computers."))
                            .font(.caption).foregroundStyle(Theme.riskMed)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private func repositorySection(_ entries: [RepositoryCatalog.Entry], title: String) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    NavigationLink {
                        RepositoryCatalogDetailView(repositoryId: entry.id, model: model, onOpenSession: onOpenSession)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: entry.isGit ? "folder" : "square.stack")
                                .frame(width: 24).foregroundStyle(Theme.codex)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).foregroundStyle(Theme.ink)
                                Text(RepositoryCatalogPresentation.identity(entry))
                                    .font(.caption).foregroundStyle(Theme.muted)
                                Text(String(format: L("Mesh: %@"), entry.memberships.map(\.name).joined(separator: ", ")))
                                    .font(.caption).foregroundStyle(Theme.codex).lineLimit(2)
                            }
                        }
                    }
                    .accessibilityIdentifier("repositories.row.\(entry.id)")
                }
            }
        }
    }
}
