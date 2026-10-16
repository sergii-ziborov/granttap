import Foundation

@MainActor
extension AppModel {
    /// Only owned, paired computers with a Project checkout receive the scoped transport plan.
    func ensureProjectComputerNetwork(for session: SessionInfo, targetComputer: String) async throws {
        guard let projectId = session.projectId, let sourceComputer = session.computerId else {
            throw ProjectNetworkError.invalidScope
        }
        if sourceComputer == targetComputer { return }
        try await configureProjectComputerNetwork(projectId: projectId, required: [sourceComputer, targetComputer])
    }

    func configureProjectComputerNetwork(projectId: String, required: Set<String>? = nil,
                                         routingEnabled: Bool? = nil, allowCrossPlatform: Bool? = nil) async throws {
        guard agentMeshPreferences.meshEnabled, let snapshot = meshSnapshots[projectId] else {
            throw ProjectNetworkError.invalidScope
        }
        let owned = ownComputerRooms(for: projectId)
        var pairings: [String: Pairing] = [:]
        var endpoints: [ProjectNetworkEndpoint] = []
        var nativeEndpointId: String?
        #if targetEnvironment(macCatalyst)
        if let localId = localMCPReader?.status?.endpointId,
           snapshot.bindings?.contains(where: { $0.endpointId == localId && $0.available }) == true {
            let endpoint = try await ProjectNetworkNative.descriptor(projectId: projectId)
            guard endpoint.id == localId else { throw ProjectNetworkError.invalidScope }
            nativeEndpointId = localId
            endpoints.append(endpoint)
        }
        #endif
        for binding in snapshot.bindings ?? [] where binding.available {
            guard !endpoints.contains(where: { $0.id == binding.endpointId }),
                  let room = meshComputerRoomByEndpointId[binding.endpointId], owned.contains(room),
                  let client = relaysByRoom[room], !client.pairing.isHub,
                  client.pairing.pushAuth?.isEmpty == false else { continue }
            var pairing = client.pairing
            pairing.relayUrl = client.resolvedRelayURL ?? pairing.relayUrl
            pairings[binding.endpointId] = pairing
            endpoints.append(.init(id: binding.endpointId, room: room, relayUrl: pairing.relayUrl,
                publicKey: pairing.peerPublicKey, controllerPublicKey: pairing.myPublicKey))
        }
        if let required, !required.isSubset(of: Set(endpoints.map(\.id))) { throw ProjectNetworkError.invalidScope }
        try await computerNetwork.ensure(projectId: projectId, endpoints: endpoints, pairings: pairings,
            requiredEndpoints: required, nativeEndpointId: nativeEndpointId, routingEnabled: routingEnabled,
            allowCrossPlatform: allowCrossPlatform) { [weak self] command, endpoint in
                self?.relaysByRoom[endpoint.room]?.send(payload: command, ttl: 24 * 60 * 60)
            }
    }
}
