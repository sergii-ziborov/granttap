#if DEBUG
import Foundation

enum DemoLongTranscript {
    @MainActor
    static func apply(to model: AppModel, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_LONG_TRANSCRIPT"] == "1" else { return }
        model.activities[AppModelDemoFixtures.codexSessionId] = activity(
            sessionId: AppModelDemoFixtures.codexSessionId, at: now)
        model.pending = []
        model.questions = []
    }

    static func activity(sessionId: String, at now: Double) -> SessionActivity {
        let entries = (0..<5_000).map { index in
            let request = index == 0 || index == 4_990
            let text = request ? (index == 0 ? "First saved request" : "Latest saved request")
                : "Saved response \(index)\n\n**Recorded evidence**\n\n"
                    + String(repeating: "A retained transcript line with source evidence.\n", count: 5)
            return ActivityEntry(id: "long-\(index)", kind: request ? "user" : "message",
                                 text: text, createdAt: now - 5_000 + Double(index))
        }
        return SessionActivity(sessionId: sessionId, agent: "codex", state: "idle",
                               entries: entries, generatedAt: now, history: .init(hasMore: false))
    }
}
#endif
