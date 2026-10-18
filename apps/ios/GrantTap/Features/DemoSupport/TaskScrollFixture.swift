#if DEBUG
import Foundation

enum TaskScrollFixture {
    @MainActor static func apply(to model: AppModel) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_TASK_SCROLL"] == "1" else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        model.pending = []; model.questions = []; model.meshSnapshots = [:]
        model.sessions = (0..<240).map { index in
            SessionInfo(sessionId: "scroll-task-\(index)", agent: "codex",
                title: String(format: "Scroll task %03d", index), state: "idle", startedAt: now,
                lastActivityAt: now - Double(index) * 1_000, tokensSession: 0, tokensLastTurn: 0)
        }
        Task { @MainActor [weak model] in
            for tick in 0..<800 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let model, model.demoMode, model.sessions.count == 240 else { return }
                model.sessions[tick % 240].tokensSession += 1
            }
        }
    }
}
#endif
