import SwiftUI

/// Shared Skills from the Project snapshot and MCP servers its chats reported.
/// Governance remains the authority; this list never grants permission.
struct ProjectToolsSkillsView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var catalog: ProjectToolsSkillsPresentation.Catalog {
        ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            usage: CapabilityUsageStore.shared.events
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
