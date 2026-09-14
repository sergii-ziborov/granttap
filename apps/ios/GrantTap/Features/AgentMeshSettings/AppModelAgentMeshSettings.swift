import Foundation

@MainActor
extension AppModel {
    func setProviderEnabled(_ provider: String, enabled: Bool) {
        let normalized = AgentIdentity.normalize(provider)
        guard AgentIdentity.knownIds.contains(normalized) else { return }
        agentMeshPreferences.providerSettings[normalized] = enabled
        AgentMeshPreferencesStore.save(agentMeshPreferences)
        for client in relaysByRoom.values {
            client.sendAgentMeshConfig(provider: normalized, providerEnabled: enabled)
        }
        AuditStore.shared.record(
            "provider", detail: "\(AgentIdentity.displayName(normalized)) \(enabled ? "enabled" : "disabled")"
        )
    }

    func setProjectMeshEnabled(_ enabled: Bool) {
        agentMeshPreferences.meshEnabled = enabled
        AgentMeshPreferencesStore.save(agentMeshPreferences)
        for client in relaysByRoom.values { client.sendAgentMeshConfig(meshEnabled: enabled) }
        if !enabled {
            pendingMeshEvents.removeAll()
            meshEventSourceRooms.removeAll()
            meshAttentionStates.removeAll()
            persistMeshState()
        }
        sendGrokBotPolicy()
        AuditStore.shared.record("mesh", detail: enabled ? "Project Mesh enabled" : "Project Mesh disabled")
    }

    func providerDisableRequiresConfirmation(_ provider: String) -> Bool {
        let normalized = AgentIdentity.normalize(provider)
        if pending.contains(where: { AgentIdentity.normalize($0.agent) == normalized }) { return true }
        if questions.contains(where: { event in
            guard let sessionId = event.sessionId else { return false }
            return allKnownSessions.first(where: { $0.sessionId == sessionId })
                .map { AgentIdentity.normalize($0.agent) == normalized } ?? false
        }) { return true }
        return meshSnapshots.values.contains { snapshot in
            snapshot.events.contains { event in
                guard event.eventType == "HANDOFF_REQUEST",
                      let capsule = event.payload.capsule else { return false }
                let touchesProvider = (capsule.sourceProvider != "grok_bot"
                    && AgentIdentity.normalize(capsule.sourceProvider) == normalized)
                    || (capsule.targetProvider != "grok_bot"
                        && AgentIdentity.normalize(capsule.targetProvider) == normalized)
                return touchesProvider && !snapshot.events.contains { later in
                    later.taskId == event.taskId && later.createdAt >= event.createdAt
                        && ["HANDOFF_ACCEPTED", "HANDOFF_REJECTED"].contains(later.eventType)
                }
            }
        }
    }

    var allKnownSessions: [SessionInfo] {
        var byId: [String: SessionInfo] = [:]
        for session in sessions + sessionHistory + Array(archivedSessions.values) {
            byId[session.sessionId] = session
        }
        return Array(byId.values)
    }

    func syncAgentMeshSettings(to client: RelayClient) {
        for provider in AgentIdentity.knownIds {
            client.sendAgentMeshConfig(
                provider: provider,
                providerEnabled: agentMeshPreferences.isProviderEnabled(provider)
            )
        }
        client.sendAgentMeshConfig(meshEnabled: agentMeshPreferences.meshEnabled)
    }
}
