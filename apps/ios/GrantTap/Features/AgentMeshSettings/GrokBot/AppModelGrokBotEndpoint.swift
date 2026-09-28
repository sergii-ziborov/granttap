import Foundation

@MainActor
extension AppModel {
    func startGrokBotEndpointIfNeeded() {
        guard let connection = grokBotConnection,
              connection.credential.status == "active" else { return }
        attachGrokBotEndpoint(connection)
    }

    func attachGrokBotEndpoint(_ connection: GrokBotEndpointConnection) {
        let endpointId = connection.endpoint.endpointId
        meshEndpointRelaysById[endpointId]?.disconnect()
        let client = RelayClient(pairing: connection.phonePairing)
        meshEndpointRoomToId[connection.phonePairing.room] = endpointId
        client.onConnectionChange = { [weak self, weak client] up in
            guard let self, let client else { return }
            self.noteGrokBotConnection(up, endpointId: endpointId, client: client)
        }
        client.onMeshEvent = { [weak self] event in
            guard let self,
                  self.acceptsGrokBotEvent(event, endpointId: endpointId) else { return }
            self.receive(event, fromRoom: connection.phonePairing.room)
        }
        meshEndpointRelaysById[endpointId] = client
        client.connect()
    }

    func noteGrokBotConnection(_ up: Bool, endpointId: String, client: RelayClient) {
        guard var connection = grokBotConnection,
              connection.endpoint.endpointId == endpointId,
              connection.credential.status == "active" else { return }
        connection.endpoint.status = up ? "active" : "pending"
        connection.actors = connection.actors.map { actor in
            var updated = actor
            if !up { updated.status = "offline" }
            else if updated.status == "offline" { updated.status = "idle" }
            return updated
        }
        saveGrokBotConnection(connection)
        if up {
            sendGrokBotPolicy(using: client)
            syncGrokBotProjects(using: client, connection: connection)
        }
    }

    func setGrokBotActorEnabled(_ actorId: String, enabled: Bool) {
        guard var connection = grokBotConnection,
              connection.credential.status == "active",
              connection.actors.contains(where: { $0.actorId == actorId }) else { return }
        connection.actors = connection.actors.map { actor in
            guard actor.actorId == actorId else { return actor }
            var updated = actor
            updated.enabled = enabled
            if !enabled { updated.status = "offline" }
            return updated
        }
        connection.policy = nextGrokBotPolicy(connection: connection)
        if !enabled { removeGrokBotClaims(actorIds: Set([actorId])) }
        saveGrokBotConnection(connection)
        sendGrokBotPolicy()
    }

    func revokeGrokBotConnection() {
        guard var connection = grokBotConnection,
              connection.credential.status != "revoked" else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        connection.credential.status = "revoked"
        connection.credential.revokedAt = now
        connection.endpoint.status = "revoked"
        connection.policy = GrokBotEndpointPolicy(
            type: "mesh.endpoint.policy", endpointId: connection.endpoint.endpointId,
            credentialId: connection.credential.credentialId, enabled: false, status: "revoked",
            projectIds: connection.credential.projectIds,
            actors: connection.actors.map { .init(actorId: $0.actorId, enabled: false) },
            revision: connection.policy.revision + 1, createdAt: now
        )
        removeGrokBotClaims(actorIds: Set(connection.actors.map(\.actorId)))
        saveGrokBotConnection(connection)
        let client = meshEndpointRelaysById[connection.endpoint.endpointId]
        client?.send(payload: connection.policy, ttl: 60) { [weak self, weak client] _ in
            Task { @MainActor in
                client?.disconnect()
                self?.meshEndpointRelaysById[connection.endpoint.endpointId] = nil
                self?.meshEndpointRoomToId[connection.phonePairing.room] = nil
            }
        }
        if client == nil {
            meshEndpointRoomToId[connection.phonePairing.room] = nil
        }
    }

    func sendGrokBotPolicy() {
        guard var connection = grokBotConnection,
              connection.credential.status == "active" else { return }
        connection.policy = nextGrokBotPolicy(connection: connection)
        saveGrokBotConnection(connection)
        guard let client = meshEndpointRelaysById[connection.endpoint.endpointId] else {
            if agentMeshPreferences.meshEnabled { attachGrokBotEndpoint(connection) }
            return
        }
        if agentMeshPreferences.meshEnabled, !client.wantsConnection { client.connect() }
        sendGrokBotPolicy(using: client)
        if !agentMeshPreferences.meshEnabled { client.disconnect() }
    }

    private func sendGrokBotPolicy(using client: RelayClient) {
        guard let policy = grokBotConnection?.policy else { return }
        client.send(payload: policy, ttl: 5 * 60)
    }

    private func nextGrokBotPolicy(
        connection: GrokBotEndpointConnection
    ) -> GrokBotEndpointPolicy {
        GrokBotEndpointPolicy(
            type: "mesh.endpoint.policy", endpointId: connection.endpoint.endpointId,
            credentialId: connection.credential.credentialId,
            enabled: agentMeshPreferences.meshEnabled, status: "active",
            projectIds: connection.credential.projectIds,
            actors: connection.actors.map { .init(actorId: $0.actorId, enabled: $0.enabled) },
            revision: connection.policy.revision + 1,
            createdAt: Date().timeIntervalSince1970 * 1_000
        )
    }

    private func saveGrokBotConnection(_ connection: GrokBotEndpointConnection) {
        guard GrokBotEndpointStore.save(connection) else {
            append("Grok Bot endpoint storage failed")
            return
        }
        grokBotConnection = connection
    }

    private func acceptsGrokBotEvent(_ event: ProjectMeshEvent, endpointId: String) -> Bool {
        GrokBotAuthorization.accepts(
            event, endpointId: endpointId, connection: grokBotConnection,
            meshEnabled: agentMeshPreferences.meshEnabled
        )
    }

    private func syncGrokBotProjects(
        using target: RelayClient, connection: GrokBotEndpointConnection
    ) {
        guard agentMeshPreferences.meshEnabled else { return }
        for projectId in connection.credential.projectIds {
            guard let snapshot = meshSnapshots[projectId],
                  let sourceRoom = (meshProjectSourceRooms[projectId] ?? [])
                    .first(where: { relaysByRoom[$0] != nil }),
                  let key = relaysByRoom[sourceRoom]?.sessionKey(for: projectId)
            else { continue }
            target.forwardMesh(snapshot, scopeId: projectId, key: key, purpose: "project")
        }
    }

    private func removeGrokBotClaims(actorIds: Set<String>) {
        for (projectId, var snapshot) in meshSnapshots {
            let owners = Set(snapshot.executions.filter {
                $0.provider == "grok_bot" && $0.actorId.map(actorIds.contains) == true
            }.map(\.sessionId))
            snapshot.claims.removeAll { owners.contains($0.ownerSessionId) }
            meshSnapshots[projectId] = snapshot
        }
        persistMeshState()
    }
}
