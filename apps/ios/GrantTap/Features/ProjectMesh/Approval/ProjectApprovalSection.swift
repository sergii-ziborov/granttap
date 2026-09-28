import SwiftUI

struct ProjectApprovalSection: View {
    let projectId: String
    @ObservedObject var model: AppModel

    private var computers: [LinkedComputer] {
        let rooms = model.meshProjectSourceRooms[projectId] ?? []
        return model.connectionRegistry.connections
            .filter { rooms.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        Section {
            Picker(L("Mesh level"), selection: Binding(
                get: { model.desiredProjectAutoAcceptLevel(projectId: projectId) },
                set: { _ = model.setProjectAutoAccept(projectId: projectId, level: $0) }
            )) {
                ForEach(AutoAcceptLevel.allCases) { level in
                    Text(level.title).tag(level.rawValue)
                }
            }
            .accessibilityIdentifier("project.auto-accept.level")
            #if targetEnvironment(macCatalyst)
            if let reader = model.localMCPReader, reader.isReady {
                MacLocalProjectApprovalRow(projectId: projectId, reader: reader, model: model)
            }
            #endif
            if computers.isEmpty && !hasLocalComputer {
                Text(L("No computer is available to apply this Mesh's auto-accept level."))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(computers) { computer in
                endpointRow(computer)
                .padding(.vertical, 3)
            }
        } header: {
            Text(L("Auto-accept"))
        } footer: {
            Text(L("This level belongs to this Mesh. Each computer reports its applied value separately; mandatory Governance and host restrictions still win."))
        }
        .onAppear {
            if !hasLocalComputer { model.migrateProjectAutoAcceptIfNeeded(projectId: projectId) }
        }
        #if targetEnvironment(macCatalyst)
        .task(id: projectId) { await model.refreshLocalProjectApproval(projectId: projectId) }
        #endif
    }

    private var hasLocalComputer: Bool {
        #if targetEnvironment(macCatalyst)
        return model.localMCPReader?.isReady == true
        #else
        return false
        #endif
    }

    private func endpointRow(_ computer: LinkedComputer) -> some View {
        let live = model.snapshotForConnection(computer).phase == .live
        let desired = model.desiredProjectAutoAcceptLevel(projectId: projectId)
        let actual = model.projectAutoAcceptLevel(projectId: projectId, roomId: computer.id)
        let state = !live ? L("Offline · pending")
            : actual == desired ? L("Applied")
            : actual.map { String(format: L("Applying · currently %@"), AutoAcceptLevel.parse($0).title) }
                ?? L("Applying · not reported")
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(computer.displayName)
                Spacer()
                Text(state).font(.caption)
                    .foregroundStyle(live && actual == desired ? Theme.ok : Theme.muted)
            }
            Text(actual.map { AutoAcceptLevel.parse($0).title } ?? L("Actual state unknown"))
                .font(.caption2).foregroundStyle(Theme.muted)
        }
        .accessibilityIdentifier("project.auto-accept.\(computer.id)")
    }
}

struct ProjectAutoAcceptView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            ProjectApprovalSection(projectId: snapshot.projectId, model: model)
            Section {
                NavigationLink {
                    ProjectActionRulesView(project: snapshot.project, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Configure action rules"))
                        Text(L("Set Allow, Ask, or Deny per capability and named tool."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("project.auto-accept.rules")
                if let policy = model.projectGovernance[snapshot.projectId]?.policy {
                    let denied = policy.rules.filter { $0.effect == .deny }.count
                    let asked = policy.rules.filter { $0.effect == .ask }.count
                    CompatLabeledContent(L("Current rules"), value: String(
                        format: L("%d deny · %d ask"), denied, asked
                    ))
                } else {
                    Text(L("No action rules yet. Configure the rules for this Mesh here."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            } header: {
                Text(L("Rules"))
            } footer: {
                Text(L("The Mesh level is a fallback. A Deny rule and mandatory host restrictions still block the action; Ask requires a person."))
            }
        }
        .pageNavigationTitle(L("Auto-accept"))
    }
}
