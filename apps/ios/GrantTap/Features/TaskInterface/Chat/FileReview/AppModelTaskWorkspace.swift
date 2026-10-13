import Foundation

@MainActor
extension AppModel {
    func cachedTaskWorkspace(for session: SessionInfo, mode: String, path: String,
                             offset: Int = 0) -> TaskWorkspaceSnapshot? {
        guard workspaceReadAllowed(session, mode: mode, offset: offset) else { return nil }
        return TaskWorkspaceStore.shared.load(scope: imageStorageScope(session.sessionId),
            sessionId: session.sessionId, mode: mode, path: path, offset: offset)
    }

    func readTaskWorkspace(for session: SessionInfo, mode: String, path: String,
                           offset: Int = 0) async throws -> TaskWorkspaceSnapshot {
        guard workspaceReadAllowed(session, mode: mode, offset: offset), path.count <= 4_096 else {
            throw URLError(.resourceUnavailable)
        }
        let scope = imageStorageScope(session.sessionId), generation = replicaGeneration
        let query = TaskWorkspaceQuery(sessionId: session.sessionId, requestId: UUID().uuidString,
            mode: mode, path: path, offset: offset, createdAt: Date().timeIntervalSince1970 * 1_000)
        let result: TaskWorkspaceSnapshot
        do {
            #if targetEnvironment(macCatalyst)
            if usesLocalMCP(for: session), let reader = localMCPReader {
                result = try await reader.workspacePreview(for: session, query: query)
            } else {
                result = try await remoteWorkspace(query)
            }
            #else
            result = try await remoteWorkspace(query)
            #endif
        } catch {
            try Task.checkCancellation()
            guard generation == replicaGeneration else { throw CancellationError() }
            if let cached = cachedTaskWorkspace(for: session, mode: mode, path: path, offset: offset) {
                return cached
            }
            throw error
        }
        try Task.checkCancellation()
        guard generation == replicaGeneration, scope == imageStorageScope(session.sessionId),
              result.isWellFormed else { throw CancellationError() }
        TaskWorkspaceStore.shared.save(result, scope: scope, mode: mode, offset: offset)
        return result
    }

    private func workspaceReadAllowed(_ session: SessionInfo, mode: String, offset: Int) -> Bool {
        guard ["directory", "file"].contains(mode), offset >= 0 else { return false }
        if case .ambiguous = sessionRoomOwnership(forSessionId: session.sessionId) { return false }
        return true
    }

    private func remoteWorkspace(_ query: TaskWorkspaceQuery) async throws -> TaskWorkspaceSnapshot {
        guard let client = relayForSession(query.sessionId),
              roomRuntime[client.pairing.room]?.socketUp == true else {
            throw URLError(.notConnectedToInternet)
        }
        return try await taskWorkspaceReads.read(query, client: client)
    }
}
