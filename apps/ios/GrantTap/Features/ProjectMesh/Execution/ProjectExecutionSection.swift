import SwiftUI

/// The live route of each Task in a Project. A message continues on that
/// execution's computer; changing computers requires a Task handoff.
struct ProjectExecutionSection: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    let onMove: (SessionInfo) -> Void
    @State private var hostChoice = "distributed"
    @State private var modelChoice = "automatic"

    private var policy: ProjectExecutionPolicy? {
        model.projectGovernance[snapshot.projectId]?.policy?.execution ?? snapshot.execution
    }

    private var ownsPinnedHost: Bool {
        guard let endpointId = policy?.targetEndpointId,
              let room = model.meshComputerRoomByEndpointId[endpointId]
        else { return false }
        return model.ownComputerRooms(for: snapshot.projectId).contains(room)
    }

    private var hostOptions: [(id: String, name: String)] {
        var names: [String: String] = [:]
        for binding in snapshot.bindings ?? [] { names[binding.endpointId] = binding.displayName }
        for catalog in snapshot.modelCatalog ?? [] where names[catalog.endpointId] == nil {
            names[catalog.endpointId] = catalog.endpointId
        }
        return names.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var modelOptions: [ProjectAdvertisedModel] {
        let endpoint = policy?.targetEndpointId
        var seen = Set<String>()
        return (snapshot.modelCatalog ?? [])
            .filter { endpoint == nil || $0.endpointId == endpoint }
            .flatMap(\.models)
            .filter { seen.insert("\($0.provider)\u{1f}\($0.modelId)").inserted }
            .sorted { ($0.provider, $0.modelId) < ($1.provider, $1.modelId) }
    }

    private struct Row: Identifiable {
        let task: ProjectMeshTask
        let execution: ExecutionSessionLink
        var id: String { task.taskId }
    }

    private var active: [Row] {
        let executions = ExecutionCoalescing.coalesced(snapshot.executions)
        return snapshot.tasks.compactMap { task in
            guard let owner = task.ownerSessionId,
                  let execution = executions.first(where: {
                      $0.taskId == task.taskId && $0.sessionId == owner && $0.endedAt == nil
                  }) else { return nil }
            return Row(task: task, execution: execution)
        }
    }

    var body: some View {
        Section {
            Picker(L("Mesh computer"), selection: Binding(
                get: { hostChoice },
                set: { choice in
                    let target = choice == "distributed" ? nil : choice
                    if model.setProjectExecutionHost(projectId: snapshot.projectId,
                                                     endpointId: target) { hostChoice = choice }
                }
            )) {
                Text(L("Choose for each new Task")).tag("distributed")
                ForEach(hostOptions, id: \.id) { host in
                    Text(host.name).tag(host.id)
                }
            }
            .disabled(model.projectGovernance[snapshot.projectId] == nil)
            Picker(L("Default model"), selection: Binding(
                get: { modelChoice },
                set: { choice in
                    let selected = modelOptions.first { modelKey($0) == choice }
                    if model.setProjectExecutionDefaults(
                        projectId: snapshot.projectId,
                        provider: selected?.provider, model: selected?.modelId
                    ) { modelChoice = choice }
                }
            )) {
                Text(L("Automatic")).tag("automatic")
                ForEach(modelOptions) { option in
                    Text("\(AgentIdentity.displayName(option.provider)) · \(option.label ?? option.modelId)")
                        .tag(modelKey(option))
                }
            }
            .disabled(model.projectGovernance[snapshot.projectId] == nil)
            if let policy, policy.mode == "pinned" {
                CompatLabeledContent(L("Host grant"), value: policy.hostGrantStatus)
                if ownsPinnedHost && policy.hostGrantStatus != "applied" {
                    Button(L("Allow this Mesh to use this computer")) {
                        _ = model.setProjectHostGrant(projectId: snapshot.projectId, grant: "applied")
                    }
                }
                if ownsPinnedHost && policy.hostGrantStatus != "unavailable" {
                    Button(L("Withdraw this computer's grant"), role: .destructive) {
                        _ = model.setProjectHostGrant(projectId: snapshot.projectId, grant: "unavailable")
                    }
                }
            }
            if active.isEmpty {
                Text(L("No active execution is registered for this Mesh."))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(active) { row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("\(AgentIdentity.displayName(row.execution.provider)) · \(row.execution.computerId)")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let session = session(for: row.execution) {
                        Button(L("Choose computer or agent…")) { onMove(session) }
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.vertical, 3)
            }
        } header: {
            Text(L("Execution"))
        } footer: {
            Text(L("Each new Task chooses one allowed computer. Existing messages stay with that Task's current execution until an explicit handoff."))
        }
        .onAppear {
            hostChoice = policy?.targetEndpointId ?? "distributed"
            modelChoice = policy.flatMap(policyModelKey) ?? "automatic"
        }
        .onChange(of: policy?.targetEndpointId) { hostChoice = $0 ?? "distributed" }
        .onChange(of: policy?.defaultModel) { _ in
            modelChoice = policy.flatMap(policyModelKey) ?? "automatic"
        }
    }

    private func session(for execution: ExecutionSessionLink) -> SessionInfo? {
        let id = model.resolvedSessionId(execution.sessionId)
        return (model.sessions + model.sessionHistory + Array(model.archivedSessions.values))
            .first { model.resolvedSessionId($0.sessionId) == id }
    }

    private func modelKey(_ model: ProjectAdvertisedModel) -> String {
        "\(model.provider)\u{1f}\(model.modelId)"
    }

    private func policyModelKey(_ policy: ProjectExecutionPolicy) -> String? {
        guard let provider = policy.defaultProvider, let model = policy.defaultModel else { return nil }
        return "\(provider)\u{1f}\(model)"
    }
}

struct ProjectExecutionView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var executionToMove: SessionInfo?

    var body: some View {
        List {
            ProjectExecutionSection(snapshot: snapshot, model: model) {
                executionToMove = $0
            }
        }
        .pageNavigationTitle(L("Execution"))
        .sheet(item: $executionToMove) { session in
            TaskHandoffSheet(session: session, model: model)
        }
    }
}
