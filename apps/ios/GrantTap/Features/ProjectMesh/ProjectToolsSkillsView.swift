import SwiftUI

/// Shared Skills from the Project snapshot and MCP servers its chats reported.
/// Governance remains the authority; this list never grants permission.
struct ProjectToolsSkillsView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showAdd = false

    var catalog: ProjectToolsSkillsPresentation.Catalog {
        ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            usage: CapabilityUsageStore.shared.events,
            added: model.addedToolItems(for: snapshot.projectId)
        )
    }

    var body: some View {
        List {
            if catalog.incomplete {
                Section {
                    Text(L("This catalog is incomplete."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            skillSections
            serverSections
            if catalog.isEmpty && !catalog.incomplete {
                Section {
                    Text(L("No shared skills or MCP servers reported for this Project."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle(L("Tools & Skills"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L("Add"))
                .accessibilityIdentifier("project.tools.add")
            }
        }
        .sheet(isPresented: $showAdd) {
            ProjectToolsSkillsAddSheet(snapshot: snapshot, model: model)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(L("Skill text does not grant permissions. Governance decides what may run."))
                .font(.caption2).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var skillSections: some View {
        ForEach(ProjectToolsSkillsPresentation.states, id: \.self) { state in
            let items = catalog.items(kind: .skill, state: state)
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in skillRow(item) }
                } header: {
                    Text("\(L("Skills")) · \(ProjectToolsSkillsPresentation.stateLabel(state))")
                }
            }
        }
    }

    @ViewBuilder private var serverSections: some View {
        ForEach(ProjectToolsSkillsPresentation.states, id: \.self) { state in
            let items = catalog.items(kind: .mcp, state: state)
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in skillRow(item, usage: true) }
                } header: {
                    Text("\(L("MCP servers")) · \(ProjectToolsSkillsPresentation.stateLabel(state))")
                }
            }
        }
    }

    private func skillRow(_ item: ProjectToolsSkillsPresentation.Item, usage: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
            if !item.detail.isEmpty {
                Text(item.detail).font(.caption).foregroundStyle(Theme.muted)
            }
            if usage {
                Text(String(
                    format: L("Usage: %@"),
                    ProjectToolsSkillsPresentation.usageLabel(name: item.name, usedNames: catalog.usedNames)
                        ?? L("Unknown")
                ))
                .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("project.tools.\(item.kind.rawValue).\(item.name)")
    }
}

/// Allow a skill or MCP already on a linked computer, and keep it on this list.
struct ProjectToolsSkillsAddSheet: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ProjectToolsSkillsPresentation.Kind = .skill
    @State private var name = ""

    var catalog: ProjectToolsSkillsPresentation.Catalog {
        ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            usage: CapabilityUsageStore.shared.events,
            added: model.addedToolItems(for: snapshot.projectId)
        )
    }

    var suggestions: [ProjectToolsSkillsPresentation.Item] {
        ProjectToolsSkillsPresentation.suggestions(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            catalog: catalog
        )
    }

    var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Picker(L("Kind"), selection: $kind) {
                        Text(L("Skill")).tag(ProjectToolsSkillsPresentation.Kind.skill)
                        Text(L("MCP server")).tag(ProjectToolsSkillsPresentation.Kind.mcp)
                    }
                    TextField(L("Name"), text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("project.tools.add.name")
                } footer: {
                    Text(L("This allows a skill or MCP already on a linked computer. Governance still decides what may run."))
                }
                if !suggestions.isEmpty {
                    Section(L("On this Project's computers")) {
                        ForEach(suggestions) { item in
                            Button {
                                model.addProjectTool(
                                    projectId: snapshot.projectId, kind: item.kind,
                                    name: item.name, snapshot: snapshot
                                )
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).foregroundStyle(Theme.ink)
                                    Text(item.kind == .skill ? L("Skill") : L("MCP server"))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            .accessibilityIdentifier("project.tools.add.suggest.\(item.name)")
                        }
                    }
                }
            }
            .navigationTitle(L("Add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add")) { addTyped() }
                        .disabled(!canAdd)
                        .accessibilityIdentifier("project.tools.add.confirm")
                }
            }
        }
    }

    private func addTyped() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.addProjectTool(
            projectId: snapshot.projectId, kind: kind, name: trimmed, snapshot: snapshot
        )
        dismiss()
    }
}
