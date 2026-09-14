import Foundation

@MainActor
extension AppModel {
    var meshNeedsYouEvents: [ProjectMeshEvent] {
        guard agentMeshPreferences.meshEnabled else { return [] }
        let now = Date().timeIntervalSince1970 * 1_000
        return pendingMeshEvents.filter { event in
            switch meshAttentionStates[event.eventId]?.status ?? .pending {
            case .pending: return true
            case .snoozed:
                return meshAttentionStates[event.eventId]?.snoozedUntil.map { $0 <= now } ?? true
            case .answered, .declined, .acknowledged, .resolved: return false
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The secondary action is semantic, never a generic deletion of unresolved work.
    func performMeshSecondaryAction(_ eventId: String) {
        guard let event = pendingMeshEvents.first(where: { $0.eventId == eventId }) else { return }
        switch event.eventType {
        case "HANDOFF_REQUEST": rejectMeshHandoff(event)
        case "AGENT_QUESTION": snoozeMeshAttention(eventId)
        default: acknowledgeMeshAttention(eventId)
        }
    }

    /// Compatibility for notification/watch callers; behavior is now type-specific.
    func dismissMeshEvent(_ eventId: String) {
        performMeshSecondaryAction(eventId)
    }

    func resolveMeshAttention(_ eventId: String, status: ProjectMeshAttentionStatus) {
        updateMeshAttentionState(eventId, status: status)
        pendingMeshEvents.removeAll { $0.eventId == eventId }
        meshEventSourceRooms[eventId] = nil
        persistMeshState()
        NotificationManager.shared.clear(eventId)
        pushToWatch()
    }

    private func snoozeMeshAttention(_ eventId: String) {
        let wakeAt = Date().timeIntervalSince1970 * 1_000 + 60 * 60_000
        updateMeshAttentionState(eventId, status: .snoozed, snoozedUntil: wakeAt)
        persistMeshState()
        NotificationManager.shared.clear(eventId)
        pushToWatch()
    }

    private func acknowledgeMeshAttention(_ eventId: String) {
        updateMeshAttentionState(eventId, status: .acknowledged)
        persistMeshState()
        NotificationManager.shared.clear(eventId)
        pushToWatch()
    }

    private func updateMeshAttentionState(
        _ eventId: String,
        status: ProjectMeshAttentionStatus,
        snoozedUntil: Double? = nil
    ) {
        let now = Date().timeIntervalSince1970 * 1_000
        let event = pendingMeshEvents.first { $0.eventId == eventId }
        var state = meshAttentionStates[eventId] ?? .init(status: .pending)
        state.status = status
        state.snoozedUntil = snoozedUntil
        state.createdAt = state.createdAt ?? event?.createdAt
        state.presentedAt = state.presentedAt ?? now
        state.updatedAt = now
        meshAttentionStates[eventId] = state
    }

    private func rejectMeshHandoff(_ request: ProjectMeshEvent) {
        guard let room = meshEventSourceRooms[request.eventId]
                ?? sourceRoom(forSessionId: request.sourceSessionId),
              let relay = meshRelay(forRoom: room),
              relay.sessionKey(for: request.taskId) != nil else {
            append("handoff decline unavailable")
            return
        }
        let createdAt = Date().timeIntervalSince1970 * 1_000
        let rejection = ProjectMeshEvent(
            type: "mesh.event", sessionId: request.taskId,
            eventId: "reject-\(UUID().uuidString)", projectId: request.projectId,
            taskId: request.taskId, sourceSessionId: "user:phone",
            targetSessionId: request.sourceSessionId, eventType: "HANDOFF_REJECTED",
            createdAt: createdAt, expiresAt: createdAt + 24 * 60 * 60_000,
            payload: .init(reason: "The user declined this handoff.")
        )
        relay.sendSession(payload: rejection, sessionId: request.taskId, ttl: 24 * 60 * 60)
        mergeMeshEvent(rejection, nowMs: createdAt)
        resolveMeshAttention(request.eventId, status: .declined)
    }
}
