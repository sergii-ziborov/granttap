import Foundation

@MainActor
extension AppModel {
    func isReplicaSessionVisible(_ session: SessionInfo) -> Bool {
        #if targetEnvironment(macCatalyst)
        if usesLocalMCP(for: session) { return true }
        #endif
        var sources = Set(sessionSourceRooms[session.sessionId] ?? [])
        sources.formUnion(sessionSourceRooms[resolvedSessionId(session.sessionId)] ?? [])
        if !sources.isEmpty { return !sources.intersection(accountVisibleRooms()).isEmpty }
        // Legacy unscoped catalogs are readable only with an unambiguous route.
        return connectionRegistry.connections.filter { !$0.pairing.isHub }.count <= 1
    }

    /// Catalog-driven work resumes after reconnect/foreground without opening a chat.
    func syncOfflineConversations(now: Double = Date().timeIntervalSince1970 * 1_000) {
        guard !demoMode else { return }
        let active = Dictionary(sessions.map { ($0.sessionId, $0) },
                                uniquingKeysWith: { first, _ in first })
        let available = Set(active.keys.filter { id in
            #if targetEnvironment(macCatalyst)
            if let session = active[id], usesLocalMCP(for: session) { return true }
            #endif
            guard let client = relayForSession(id), let room = roomId(for: client) else { return false }
            return roomRuntime[room]?.socketUp == true
        })
        let requests = transcriptBackfill.next(activeIds: Set(active.keys), activities: activities,
                                               available: available,
                                               versions: active.mapValues(\.lastActivityAt), now: now)
        // Saved pictures must not wait for a long transcript backlog to finish.
        for id in available { if let saved = activities[id] { enqueueReplicaImages(saved) } }
        for request in requests {
            #if targetEnvironment(macCatalyst)
            if let session = active[request.sessionId], usesLocalMCP(for: session),
               let reader = localMCPReader {
                let generation = replicaGeneration
                Task { [weak self] in
                    do {
                        let activity = try await reader.activity(for: session, cursor: request.cursor)
                        guard let self, self.replicaGeneration == generation else { return }
                        MacLocalProjection.apply(activity, for: session, to: self)
                    } catch {
                        self?.transcriptBackfill.failed(request,
                            now: Date().timeIntervalSince1970 * 1_000)
                    }
                }
                continue
            }
            #endif
            relayForSession(request.sessionId)?.requestSessionEvents(
                sessionId: request.sessionId, history: true, historyCursor: request.cursor)
        }
    }

    func replicaActivityArrived(_ activity: SessionActivity) {
        guard !demoMode else { return }
        transcriptBackfill.received(activity, now: Date().timeIntervalSince1970 * 1_000)
        enqueueReplicaImages(activity)
        adoptTranscriptTitle(activity)
        for thread in Set(activity.entries.compactMap(\.childThreadId)) {
            requestThreadEvents(activity.sessionId, threadId: thread)
        }
        syncOfflineConversations()
    }
}
