import Foundation

@MainActor
final class TaskWorkspaceReadBroker {
    private struct Pending {
        let query: TaskWorkspaceQuery
        let room: String
        let completion: CheckedContinuation<TaskWorkspaceSnapshot, Error>
    }
    private var pending: [String: Pending] = [:]

    func read(_ query: TaskWorkspaceQuery, client: RelayClient,
              timeoutNanoseconds: UInt64 = 12_000_000_000) async throws -> TaskWorkspaceSnapshot {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { completion in
                pending[query.requestId] = Pending(query: query, room: client.pairing.room,
                                                   completion: completion)
                client.sendSession(payload: query, sessionId: query.sessionId, ttl: 30) { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.fail(query.requestId, error: error) }
                }
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    self?.fail(query.requestId, error: URLError(.timedOut))
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.fail(query.requestId, error: CancellationError()) }
        })
    }

    func receive(_ snapshot: TaskWorkspaceSnapshot, fromRoom room: String) {
        guard snapshot.isWellFormed, let waiting = pending[snapshot.requestId],
              waiting.room == room, waiting.query.sessionId == snapshot.sessionId,
              waiting.query.path == snapshot.path,
              snapshot.nextOffset == nil || snapshot.nextOffset! > waiting.query.offset,
              snapshot.unavailable == true || (waiting.query.mode == "directory"
                ? snapshot.entries != nil : snapshot.text != nil) else { return }
        pending.removeValue(forKey: snapshot.requestId)
        if snapshot.unavailable == true {
            waiting.completion.resume(throwing: URLError(.resourceUnavailable))
        } else {
            waiting.completion.resume(returning: snapshot)
        }
    }

    func cancel() {
        for id in Array(pending.keys) { fail(id, error: CancellationError()) }
    }

    private func fail(_ id: String, error: Error) {
        pending.removeValue(forKey: id)?.completion.resume(throwing: error)
    }
}
