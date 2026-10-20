#if DEBUG
import Foundation

@MainActor
enum DemoWorkspaceRead {
    static let completion = DemoWorkspaceReadCompletion()

    static func enabled(_ model: AppModel) -> Bool {
        model.demoMode && ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_WORK"] == "loading"
    }

    static func read(_ query: TaskWorkspaceQuery, model: AppModel) async throws -> TaskWorkspaceSnapshot? {
        guard enabled(model) else { return nil }
        try await completion.wait()
        return TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: query.sessionId,
            requestId: query.requestId, path: query.path,
            entries: query.mode == "directory" ? [] : nil,
            text: query.mode == "file" ? "Fixture preview" : nil, truncated: false, createdAt: query.createdAt)
    }
}

@MainActor
final class DemoWorkspaceReadCompletion {
    private var completed = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func wait() async throws {
        try Task.checkCancellation()
        guard !completed else { return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters[id] = continuation }
            }
        }, onCancel: {
            Task { @MainActor in
                self.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        })
        try Task.checkCancellation()
    }

    func finish() {
        completed = true
        let pending = Array(waiters.values)
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
#endif
