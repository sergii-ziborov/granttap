import Foundation

@MainActor
extension AppModel {
    /// A native permission proves that its session exists, even before the next
    /// catalog scan. Keep an inspectable row; the real catalog replaces its title.
    func ensureApprovalChat(_ request: ApprovalRequest, fromRoom room: String) {
        guard let id = Self.normalizedApprovalSession(request.sessionId),
              connectionRegistry.connections.contains(where: { $0.id == room }) else { return }
        rememberSessionSourceRoom(room, sessionId: id)
        guard sessionSourceRooms[id] == [room] else { return }
        if (sessions + sessionHistory).contains(where: {
            $0.childThreads?.contains(where: { $0.threadId == id }) == true
        }) { return }
        guard !sessions.contains(where: { $0.sessionId == id }) else { return }
        let existing = sessionHistory.first { $0.sessionId == id } ?? archivedSessions[id]
        let leaf = request.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let name = leaf.map { "\(request.agent) · \($0)" } ?? request.agent
        var session = existing ?? SessionInfo(sessionId: id, agent: request.agent,
            title: name, cwd: request.cwd, branch: nil, model: nil, state: "waiting",
            startedAt: request.createdAt, lastActivityAt: request.createdAt,
            tokensSession: 0, tokensLastTurn: 0)
        session.state = "waiting"
        session.lastActivityAt = max(session.lastActivityAt, request.createdAt)
        sessions.insert(session, at: 0)
        sessionHistory.removeAll { $0.sessionId == id }
        replicaSessionIndex[id] = session
        SessionCatalogCache.save(.init(sessions: sessions, history: sessionHistory,
            machine: machineName, tokensRecent: tokensRecent, tokenWindowHours: tokenWindowHours,
            generatedAt: lastSessionsGeneratedAt))
        syncOfflineConversations()
    }

    func approvalChatId(_ request: ApprovalRequest) -> String? {
        guard let id = Self.normalizedApprovalSession(request.sessionId) else { return nil }
        return (sessions + sessionHistory).first {
            $0.childThreads?.contains(where: { $0.threadId == id }) == true
        }?.sessionId ?? id
    }

    /// Fresh authenticated publications count as liveness, independent of a
    /// slow catalog scan. Stale durable replay cannot make a dead Mac look live.
    func noteAuthenticatedMachineActivity(fromRoom room: String, generatedAt: Double) {
        let now = Date().timeIntervalSince1970 * 1_000
        guard generatedAt >= now - 90_000, generatedAt <= now + 30_000 else { return }
        var runtime = roomRuntime[room] ?? RoomRuntime()
        runtime.lastHeartbeatAt = now
        roomRuntime[room] = runtime
        objectWillChange.send()
    }
}
