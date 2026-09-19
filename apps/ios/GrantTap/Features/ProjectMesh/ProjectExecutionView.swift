import SwiftUI

/// Project → Execution: pin new GrantTap tasks to one confirmed host.
struct ProjectExecutionView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var mode: ProjectExecutionMode
    @State private var targetId: String
    @State private var offline: ExecutionOfflineBehavior

    init(snapshot: ProjectMeshSnapshot, model: AppModel) {
        self.snapshot = snapshot
        self.model = model
        let current = snapshot.execution ?? model.projectGovernance[snapshot.projectId]?.policy?.execution
        _mode = State(initialValue: current?.mode ?? .distributed)
        _targetId = State(initialValue: current?.targetEndpointId ?? snapshot.bindings?.first?.endpointId ?? "")
        _offline = State(initialValue: current?.offlineBehavior ?? .reject)
    }

    var computers: [ProjectBindingSummary] {
        let rows = snapshot.bindings ?? []
        var seen = Set<String>()
        return rows.filter { seen.insert($0.endpointId).inserted }
    }

    var catalog: EndpointModelCatalog? {
        ProjectExecutionPresentation.catalog(snapshot: snapshot, targetId: targetId)
    }

    var body: some View {
        List {
            Section {
                Picker(L("Mode"), selection: $mode) {
                    Text(L("Distributed")).tag(ProjectExecutionMode.distributed)
                    Text(L("Pinned")).tag(ProjectExecutionMode.pinned)
                }
                if mode == .pinned {
                    Picker(L("Host"), selection: $targetId) {
                        ForEach(computers) { computer in
                            Text("\(computer.displayName) · \(String(computer.endpointId.suffix(8)))")
                                .tag(computer.endpointId)
                        }
                    }
                    Picker(L("If the host is offline"), selection: $offline) {
                        Text(L("Reject new tasks")).tag(ExecutionOfflineBehavior.reject)
                        Text(L("Queue until the deadline")).tag(ExecutionOfflineBehavior.queueUntilDeadline)
                    }
                }
                Button(L("Save execution")) {
                    _ = model.applyProjectExecution(
                        projectId: snapshot.projectId,
                        mode: mode,
                        targetEndpointId: mode == .pinned ? targetId : nil,
                        offlineBehavior: offline
                    )
                }
                .accessibilityIdentifier("project.execution.save")
            } header: {
                Text(L("Execution"))
            } footer: {
                Text(statusDetail)
            }
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
        .navigationTitle(L("Execution"))
    }

    var statusDetail: String {
        if let error = model.projectPolicyErrors[snapshot.projectId] { return error }
        return ProjectManagePresentation.executionSummary(
            snapshot, governance: model.projectGovernance[snapshot.projectId]
        )
    }
}
