import SwiftUI

/// Every Project this phone takes part in, and what can be done about each.
///
/// A Project arrives on its own when a computer reports it, so the list is
/// the mesh as the phone sees it: what each Project is doing now, on how many
/// computers, with whom. What the phone decides is its own: the name a
/// Project goes by here, whether it is shown at all, and whether to keep
/// anything about it.
struct ProjectsTabView: View {
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void = { _ in }
    @State private var renaming: ProjectListRow?
    @State private var forgetting: ProjectListRow?
    @State private var showHidden = false
    @State private var showJoin = false
    @State private var catalogTab = "mesh"

    init(model: AppModel, onOpenSession: @escaping (SessionInfo) -> Void = { _ in }, showHidden: Bool = false) {
        self.model = model
        self.onOpenSession = onOpenSession
        _showHidden = State(initialValue: showHidden)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Mesh catalog"), selection: $catalogTab) {
                Text(L("Mesh")).tag("mesh")
                Text(L("Repositories")).tag("repositories")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .accessibilityIdentifier("projects.catalog-tabs")
            Divider()
            if catalogTab == "repositories" {
                RepositoryCatalogListView(model: model, onOpenSession: onOpenSession)
            } else {
                meshList
            }
        }
    }

    @ViewBuilder private var meshList: some View {
        let rows = model.projectListRows
        let hidden = rows.filter(\.hidden)
        List {
            if rows.isEmpty {
                Section {
                    Text(L("No Mesh spaces yet. A computer shares a Mesh when an agent starts working. One Mesh can connect several repositories."))
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            groupedSections(rows.filter { !$0.hidden })
            if !hidden.isEmpty {
                Section {
                    Button {
                        withAnimation { showHidden.toggle() }
                    } label: {
                        HStack {
                            Text(String(format: L("Hidden · %d"), hidden.count)).foregroundStyle(Theme.muted)
                            Spacer()
                            Image(systemName: showHidden ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("projects.hidden.toggle")
                    if showHidden {
                        ForEach(hidden) { row in projectLink(row) }
                    }
                } footer: {
                    if showHidden {
                        Text(L("A hidden Mesh leaves the Now and Tasks lists. Forgetting drops its local Mesh data; a computer that still carries it reports it again."))
                    }
                }
            }
            #if !targetEnvironment(macCatalyst)
            Section {
                Button { showJoin = true } label: {
                    Label(L("Join a Mesh with invite"), systemImage: "qrcode")
                }
                .accessibilityIdentifier("mesh.join")
            } footer: {
                Text(L("Join a Mesh shared by another person. Computers join in Settings."))
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showJoin) {
            PairingSheet(purpose: .joinProject).environmentObject(model)
        }
        .sheet(item: $renaming) { row in
            RenameProjectSheet(row: row, model: model)
        }
        .confirmationDialog(
            forgetting.map { String(format: L("Forget “%@” on this phone?"), $0.name) } ?? "",
            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Forget Mesh"), role: .destructive) {
                if let row = forgetting { model.forgetProject(row.projectId) }
                forgetting = nil
            }
        } message: {
            Text(L("Its Tasks, Governance draft, members and key on this phone go. Nothing changes on any computer."))
        }
    }

    @ViewBuilder private func groupedSections(_ rows: [ProjectListRow]) -> some View {
        let grouped = ProjectSolutionGroups.make(rows: rows, snapshots: model.meshSnapshots)
        ForEach(grouped.solutions) { solution in
            Section {
                ForEach(solution.rows) { row in projectLink(row) }
            } header: {
                Text(String(format: L("Solution · %@"), solution.title))
            } footer: {
                Text(L("Grouped by evidenced Weavatrix relations. Each Mesh keeps its own members and permissions."))
            }
        }
        ForEach(grouped.linked) { link in
            Section {
                ForEach(link.rows) { row in projectLink(row) }
            } header: {
                Text(String(format: L("Linked Mesh spaces · %@"), link.title))
            } footer: {
                Text(L("These Mesh spaces share repositories through bindings or Task executions. Each keeps separate access; a code dependency appears only after Weavatrix verifies it."))
            }
        }
        if !grouped.ungrouped.isEmpty {
            Section {
                ForEach(grouped.ungrouped) { row in projectLink(row) }
            } header: {
                if !grouped.solutions.isEmpty || !grouped.linked.isEmpty {
                    Text(L("Other Mesh spaces"))
                }
            } footer: {
                Text(L("Solutions appear when the Engine reports an evidenced relation between repositories. Mesh spaces with the same name keep separate access. Swipe to rename or hide."))
            }
        }
    }

    @ViewBuilder
    private func projectLink(_ row: ProjectListRow) -> some View {
        if let snapshot = model.meshSnapshots[row.projectId] {
            NavigationLink {
                ProjectMeshView(snapshot: snapshot, model: model, onOpenSession: onOpenSession)
            } label: {
                ProjectListRowView(row: row, repositorySummary: RepositoryCatalogPresentation.meshSummary(snapshot))
            }
            .accessibilityIdentifier("projects.row.\(row.projectId)")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    model.setProjectHidden(row.projectId, !row.hidden)
                } label: {
                    Label(row.hidden ? L("Show") : L("Hide"), systemImage: row.hidden ? "eye" : "eye.slash")
                }
                .tint(Theme.muted)
                Button {
                    renaming = row
                } label: {
                    Label(L("Rename"), systemImage: "pencil")
                }
                .tint(Theme.codex)
            }
            .contextMenu {
                Button { renaming = row } label: { Label(L("Rename"), systemImage: "pencil") }
                Button { model.setProjectHidden(row.projectId, !row.hidden) } label: {
                    Label(row.hidden ? L("Show") : L("Hide"), systemImage: row.hidden ? "eye" : "eye.slash")
                }
                Button(role: .destructive) { forgetting = row } label: {
                    Label(L("Forget on this phone…"), systemImage: "trash")
                }
            }
        }
    }
}
