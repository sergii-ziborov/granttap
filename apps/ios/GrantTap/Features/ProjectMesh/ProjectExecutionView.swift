import SwiftUI

/// Project → Execution: new tasks on every Mesh computer, or on one of them.
struct ProjectExecutionView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var allHosts: Bool
    @State private var targetId: String
    @State private var offline: ExecutionOfflineBehavior

    init(snapshot: ProjectMeshSnapshot, model: AppModel) {
        self.snapshot = snapshot
        self.model = model
        let current = snapshot.execution ?? model.projectGovernance[snapshot.projectId]?.policy?.execution
        let pinned = current?.mode == .pinned
        _allHosts = State(initialValue: !pinned)
        _targetId = State(initialValue: current?.targetEndpointId ?? "")
        _offline = State(initialValue: current?.offlineBehavior ?? .reject)
    }

    var hosts: [String] {
        ProjectComputerRoster.hostIds(
            snapshot: snapshot,
            participating: model.computerRooms(for: snapshot.projectId),
            memberRooms: Set(model.memberLinks(for: snapshot.projectId).map(\.id)),
            archived: model.archivedComputers(for: snapshot.projectId),
            removed: model.removedComputers(for: snapshot.projectId)
        )
    }

    var catalog: EndpointModelCatalog? {
        allHosts ? nil : ProjectExecutionPresentation.catalog(snapshot: snapshot, targetId: targetId)
    }

    var body: some View {
        List {
            Section {
                Button {
                    allHosts = true
                } label: {
                    hostLabel(
                        title: L("All computers"),
                        detail: L("New tasks run on every computer that belongs to this Project."),
                        selected: allHosts
                    )
                }
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("project.execution.all")
                ForEach(hosts, id: \.self) { endpoint in
                    Button {
                        allHosts = false
                        targetId = endpoint
                    } label: {
                        hostLabel(
                            title: model.displayName(forComputer: endpoint),
                            detail: hostDetail(endpoint),
                            selected: !allHosts && targetId == endpoint
                        )
                    }
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("project.execution.host.\(endpoint)")
                }
                if !allHosts {
                    Picker(L("If the host is offline"), selection: $offline) {
                        Text(L("Reject new tasks")).tag(ExecutionOfflineBehavior.reject)
                        Text(L("Queue until the deadline")).tag(ExecutionOfflineBehavior.queueUntilDeadline)
                    }
                }
                Button(L("Save execution")) {
                    _ = model.applyProjectExecution(
                        projectId: snapshot.projectId,
                        mode: allHosts ? .distributed : .pinned,
                        targetEndpointId: allHosts ? nil : targetId,
                        offlineBehavior: offline
                    )
                }
                .disabled(!allHosts && (targetId.isEmpty || !hosts.contains(targetId)))
                .accessibilityIdentifier("project.execution.save")
            } header: {
                Text(L("Where new tasks run"))
            } footer: {
                Text(statusDetail)
            }
            if !allHosts {
                Section(L("Host models")) {
                    if let catalog, !catalog.models.isEmpty {
                        ForEach(catalog.models) { item in
                            Text(item.label ?? item.modelId)
                        }
                    } else {
                        Text(L(catalog?.reason ?? "Catalog not reported"))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .navigationTitle(L("Execution"))
        .onAppear {
            if !allHosts, targetId.isEmpty || !hosts.contains(targetId) {
                targetId = hosts.first ?? ""
            }
        }
    }

    var statusDetail: String {
        if let error = model.projectPolicyErrors[snapshot.projectId] { return error }
        return ProjectManagePresentation.executionSummary(
            snapshot, governance: model.projectGovernance[snapshot.projectId]
        )
    }

    private func hostLabel(title: String, detail: String, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Theme.ok)
            }
        }
        .padding(.vertical, 2)
    }

    private func hostDetail(_ endpoint: String) -> String {
        if let connection = model.connection(matching: endpoint) {
            return "\(model.snapshotForConnection(connection).statusTitle) · \(L("New tasks run only on this computer."))"
        }
        return L("New tasks run only on this computer.")
    }
}
