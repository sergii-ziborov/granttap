import Foundation

@MainActor
extension AppModel {
    func shouldAwaitNativeSession(_ incoming: String?, replyingToMCP: Bool) -> Bool {
        !replyingToMCP && incoming.map { localOnlySessionIds.contains($0) } == true
            && deliveries.contains {
                $0.sessionId == incoming && $0.awaitingSessionRemap != true
                    && $0.admissionRejected != true && ($0.state == .queued || $0.state == .sending)
            }
    }

    func configurePendingTaskDelivery(_ row: inout OutgoingDelivery, isNewTask: Bool) {
        row.taskOriginId = isNewTask ? row.id : nil
        guard !isNewTask, row.requestId == nil, let incoming = row.sessionId, let agent = row.agent,
              let origin = pendingTaskOrigin(sessionId: incoming, agent: agent, room: row.roomId) else { return }
        row.continuationOriginId = origin
        row.awaitingSessionRemap = true
        row.chatQueue = ChatMessageQueueContext(waiting: false, transport: .relay,
            taskId: knownSession(for: incoming, preferredAgent: agent)?.taskId,
            queuedAt: row.createdAt, relayManaged: true, notBefore: floor(row.createdAt), sendImmediately: true)
    }

    func pendingTaskOrigin(sessionId: String, agent: String, room: String?) -> String? {
        guard localOnlySessionIds.contains(sessionId), let room else { return nil }
        let canonical = AgentIdentity.normalize(agent)
        if !demoMode, let saved = try? LocalTaskOrigins.origin(sessionId: sessionId,
            agent: canonical, room: room, now: Date().timeIntervalSince1970 * 1_000) { return saved }
        return TaskDeliveryQueue.oldestFirst(deliveries).first {
            $0.sessionId == sessionId && $0.roomId == room && $0.agent == canonical
                && $0.requestId == nil && $0.admissionRejected != true && $0.continuationOriginId == nil
                && $0.taskOriginId != nil
        }?.taskOriginId
    }

    func rememberPendingTaskOrigin(_ row: OutgoingDelivery) {
        guard !demoMode, let origin = row.taskOriginId, let session = row.sessionId,
              let room = row.roomId, let agent = row.agent else { return }
        try? LocalTaskOrigins.remember(sessionId: session, agent: agent, room: room,
                                      originId: origin, at: row.createdAt)
    }

    func relayQueuedMessage(for row: OutgoingDelivery) -> UserMessage {
        var message = wireUserMessage(for: row)
        message.attachments = row.attachments
        message.attachmentRefs = nil
        if let origin = row.continuationOriginId {
            message.type = "user.message.continue"
            message.originMessageId = origin
            message.taskOriginId = nil
            message.retryId = nil
            message.sessionId = nil
            message.cwd = nil
        }
        return message
    }

    /// Resolve exact creator links after the phone missed a one-time creation event.
    func recoverPendingTaskOrigins(from native: [SessionInfo], room: String) {
        guard !localOnlySessionIds.isEmpty, accountVisibleRooms().contains(room),
              let pairing = connectionRegistry.connections.first(where: { $0.id == room })?.pairing else { return }
        var nativeIDs: [String: Set<String>] = [:]
        let linked = native.filter { $0.creationOrigins?.isEmpty == false }
        for session in Self.filterRealCatalogSessions(linked, allowDemo: demoMode) {
            for origin in session.creationOrigins ?? [] where origin.controllerPublicKey == pairing.myPublicKey {
                nativeIDs["\(AgentIdentity.normalize(session.agent)):\(origin.originId)", default: []].insert(session.sessionId)
            }
        }
        guard !nativeIDs.isEmpty else { return }
        var localIDs: [String: Set<String>] = [:]
        if !demoMode, let routes = try? LocalTaskOrigins.routes(room: room, now: Date().timeIntervalSince1970 * 1_000) {
            for route in routes where localOnlySessionIds.contains(route.session) {
                localIDs["\(route.agent):\(route.origin)", default: []].insert(route.session)
            }
        }
        for row in deliveries where row.roomId == room && row.admissionRejected != true {
            guard let session = row.sessionId, localOnlySessionIds.contains(session),
                  let agent = row.agent, let origin = row.taskOriginId ?? row.continuationOriginId else { continue }
            localIDs["\(agent):\(origin)", default: []].insert(session)
        }
        for (key, targets) in nativeIDs where targets.count == 1 {
            guard let sources = localIDs[key], sources.count == 1,
                  let source = sources.first, let target = targets.first else { continue }
            switch sessionRoomOwnership(forSessionId: source) {
            case .ambiguous: continue
            case .exact(let owner) where owner != room: continue
            default: break
            }
            rememberSessionSourceRoom(room, sessionId: source)
            if source == target {
                localOnlySessionIds.remove(source)
                persistLocalOnlySessions()
            } else { remapLocalSession(from: source, to: target) }
        }
    }
}
