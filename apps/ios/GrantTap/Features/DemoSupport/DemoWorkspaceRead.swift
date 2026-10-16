#if DEBUG
import Foundation

@MainActor
enum DemoWorkspaceRead {
    static func enabled(_ model: AppModel) -> Bool {
        model.demoMode && ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_WORK"] == "loading"
    }

    static func read(_ query: TaskWorkspaceQuery, model: AppModel) async throws -> TaskWorkspaceSnapshot? {
        guard enabled(model) else { return nil }
        try await Task.sleep(nanoseconds: 4_000_000_000)
        return TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: query.sessionId,
            requestId: query.requestId, path: query.path,
            entries: query.mode == "directory" ? [] : nil,
            text: query.mode == "file" ? "Fixture preview" : nil, truncated: false, createdAt: query.createdAt)
    }
}
#endif
