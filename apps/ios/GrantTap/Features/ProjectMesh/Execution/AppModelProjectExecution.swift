import Foundation

@MainActor
extension AppModel {
    @discardableResult
    func setProjectHostGrant(projectId: String, grant: String) -> Bool {
        guard ["applied", "unavailable"].contains(grant),
              let execution = projectGovernance[projectId]?.policy?.execution,
              execution.mode == "pinned",
              let endpointId = execution.targetEndpointId,
              let room = meshComputerRoomByEndpointId[endpointId],
              ownComputerRooms(for: projectId).contains(room),
              let relay = relaysByRoom[room] else { return false }
        relay.sendSession(payload: ProjectHostGrant(
            projectId: projectId, grant: grant, revision: execution.revision,
            instanceEpoch: instanceEpochByRoom[room],
            createdAt: Date().timeIntervalSince1970 * 1_000
        ), sessionId: projectId, ttl: 15 * 60)
        return true
    }

    /// A Project host is a policy decision sent to every bound computer. The
    /// chosen host must first be advertised by a Project binding or model catalog.
    @discardableResult
    func setProjectExecutionHost(projectId: String, endpointId: String?) -> Bool {
        guard agentMeshPreferences.meshEnabled,
              let projection = projectGovernance[projectId],
              let snapshot = meshSnapshots[projectId] else { return false }
        if let endpointId {
            let known = Set((snapshot.bindings ?? []).map(\.endpointId)
                + (snapshot.modelCatalog ?? []).map(\.endpointId))
            guard known.contains(endpointId) else { return false }
        }
        let current = projection.policy
        let revision = (current?.revision ?? 0) + 1
        var rules = current?.rules ?? []
        for index in rules.indices { rules[index].revision = revision }
        let execution = ProjectExecutionPolicy(
            mode: endpointId == nil ? "distributed" : "pinned",
            targetEndpointId: endpointId,
            defaultProvider: current?.execution?.defaultProvider,
            defaultModel: current?.execution?.defaultModel,
            revision: revision,
            hostGrantId: current?.execution?.hostGrantId,
            hostGrantStatus: endpointId == nil ? "none" : "pending",
            offlineBehavior: current?.execution?.offlineBehavior ?? "reject"
        )
        let policy = ProjectPolicy(
            projectId: projectId, revision: revision,
            enforcement: current?.enforcement ?? .bestAvailable, rules: rules,
            execution: execution, restrictions: current?.restrictions,
            environment: current?.environment
        )
        return submitProjectPolicy(policy, replacing: current)
    }

    @discardableResult
    func setProjectExecutionDefaults(
        projectId: String, provider: String?, model: String?
    ) -> Bool {
        guard let projection = projectGovernance[projectId] else { return false }
        let current = projection.policy
        let revision = (current?.revision ?? 0) + 1
        var rules = current?.rules ?? []
        for index in rules.indices { rules[index].revision = revision }
        let previous = current?.execution
        let execution = ProjectExecutionPolicy(
            mode: previous?.mode ?? "distributed",
            targetEndpointId: previous?.targetEndpointId,
            defaultProvider: provider,
            defaultModel: model,
            revision: revision,
            hostGrantId: previous?.hostGrantId,
            hostGrantStatus: previous?.hostGrantStatus ?? "none",
            offlineBehavior: previous?.offlineBehavior ?? "reject"
        )
        return submitProjectPolicy(ProjectPolicy(
            projectId: projectId, revision: revision,
            enforcement: current?.enforcement ?? .bestAvailable, rules: rules,
            execution: execution, restrictions: current?.restrictions,
            environment: current?.environment
        ), replacing: current)
    }
}
