import Foundation

extension AppModel {
    @discardableResult
    func queueChatMessage(_ text: String, to session: SessionInfo,
                          attachments: [UserAttachment] = [],
                          preferredMcp: String? = nil, skill: String? = nil,
                          overrides: TurnOverrides = .unchanged) -> Bool {
        guard text.count <= 8_000,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty else { return false }
        let now = Date().timeIntervalSince1970 * 1_000
        let transport: ChatMessageQueueContext.Transport
        #if targetEnvironment(macCatalyst)
        transport = usesLocalMCP(for: session) ? .localMCP : .relay
        #else
        transport = .relay
        #endif
        let options = overrides.wire(for: session.agent)
        let candidate = OutgoingDelivery(
            id: UUID().uuidString.lowercased(), text: text,
            agent: AgentIdentity.normalize(session.agent), cwd: nil,
            sessionId: resolvedSessionId(session.sessionId), requestId: nil,
            roomId: transport == .relay ? sourceRoom(forSessionId: session.sessionId) : nil,
            attachments: attachments, preferredMcp: preferredMcp, skill: skill,
            projectId: session.projectId, model: options.model,
            permissionMode: options.permissionMode, effort: options.effort,
            createdAt: now, updatedAt: now, attempts: 0, state: .queued,
            error: nil, nextRetryAt: nil,
            awaitingSessionRemap: localOnlySessionIds.contains(resolvedSessionId(session.sessionId)),
            chatQueue: ChatMessageQueueContext(waiting: true, transport: transport,
                                               taskId: session.taskId, queuedAt: now)
        )
        let admission = DeliveryPersistence.admit(candidate, into: deliveries)
        deliveries = admission.deliveries
        if !demoMode { persistDeliveries() }
        return admission.shouldSend
    }

    func chatQueuedMessages(for session: SessionInfo) -> [OutgoingDelivery] {
        let resolved = resolvedSessionId(session.sessionId)
        return TaskDeliveryQueue.oldestFirst(deliveries.filter {
            $0.chatQueue != nil && $0.state != .delivered
                && $0.agent == AgentIdentity.normalize(session.agent)
                && $0.sessionId.map(resolvedSessionId) == resolved
                && ($0.projectId == nil || $0.projectId == session.projectId)
                && ($0.chatQueue?.taskId == nil || $0.chatQueue?.taskId == session.taskId)
                && ($0.chatQueue?.transport == .localMCP
                    || $0.roomId == sourceRoom(forSessionId: session.sessionId))
        })
    }

    @discardableResult
    func cancelChatQueuedMessage(_ id: String) -> Bool {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              ChatMessageQueuePolicy.canCancel(deliveries[index]) else { return false }
        deliveries.remove(at: index)
        if !demoMode { persistDeliveries() }
        return true
    }

    func sendChatQueuedMessageNow(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              ChatMessageQueuePolicy.canCancel(deliveries[index]),
              deliveries[index].awaitingSessionRemap != true else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        if deliveries[index].chatQueue?.queuedAt == nil {
            deliveries[index].chatQueue?.queuedAt = deliveries[index].createdAt
        }
        // Existing expiry, preview retention and native-echo checks measure
        // the actual send. Queue ordering keeps its separate admission time.
        deliveries[index].createdAt = now
        deliveries[index].chatQueue?.waiting = false
        deliveries[index].state = .queued
        deliveries[index].attempts = 0
        deliveries[index].processingAcknowledgedAt = nil
        deliveries[index].processingRetryStartedAt = nil
        deliveries[index].attemptGeneration = nil
        deliveries[index].error = nil
        deliveries[index].nextRetryAt = nil
        deliveries[index].updatedAt = now
        appendQueuedMessageToTranscript(deliveries[index])
        if demoMode {
            deliveries[index].state = .delivered
            return
        }
        persistDeliveries()
        attemptDelivery(id)
    }

    func resumeChatQueues(observed sessions: [SessionInfo], fromRoom room: String? = nil,
                          localOnly: Bool = false) {
        #if targetEnvironment(macCatalyst)
        if localOnly { resumeLocalQueuedDeliveries() }
        #endif
        for id in ChatMessageQueuePolicy.ready(deliveries, observed: sessions) {
            guard let row = deliveries.first(where: { $0.id == id }),
                  room == nil || row.roomId == room,
                  !localOnly || row.chatQueue?.transport == .localMCP,
                  chatQueueTransportAvailable(row) else { continue }
            sendChatQueuedMessageNow(id)
        }
    }

    func chatQueueTransportAvailable(_ row: OutgoingDelivery) -> Bool {
        #if targetEnvironment(macCatalyst)
        if row.chatQueue?.transport == .localMCP { return localMCPReader?.isReady == true }
        #endif
        return row.roomId.map(deliveryRoomIsUp) == true
            && row.roomId.flatMap { relaysByRoom[$0] } != nil
    }

    private func appendQueuedMessageToTranscript(_ row: OutgoingDelivery) {
        guard let sessionId = row.sessionId else { return }
        let id = "local-user-\(row.id)"
        guard activities[sessionId]?.entries.contains(where: { $0.id == id }) != true else { return }
        appendLocalChatEntry(sessionId: sessionId, agent: row.agent ?? "codex",
                             entry: ActivityEntry(id: id, kind: "user", text: row.text,
                                 createdAt: row.updatedAt, attachments: row.attachments.map(\.name)))
    }
}
