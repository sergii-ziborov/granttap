#if DEBUG
import Foundation

@MainActor
enum DemoTranscriptHistory {
    static var enabled: Bool { ProcessInfo.processInfo.environment["GRANTTAP_TEST_TRANSCRIPT_HISTORY"] == "1" }

    static func initial(at now: Double) -> SessionActivity {
        let files = (1...7).map { index in
            let longLine = index == 7 ? "+BEGIN " + String(repeating: "source ", count: 30) + " END\n" : ""
            return RecordedFileChange(path: "/demo/file-\(index).swift", linesAdded: index, linesRemoved: 1,
                diff: "@@ -1 +1 @@\n-old value\n+new value \(index)\n" + longLine,
                diffTruncated: index == 7)
        }
        var entries = messages(in: 20..<32, prefix: "Recent", baseTime: now - 1000)
        let command = ObservedCapability(kind: .cli, name: "test", toolName: "Bash",
            commandPreview: "test", estimatedContextTokens: 320, estimatedBaselineTokens: nil,
            durationMs: 10000, outcome: .success, resource: .init(attribution: .attributed,
                cpuTimeMs: 7500, peakRssBytes: 300000000, sampleWindowMs: 10000))
        entries.append(ActivityEntry(id: "history-command", kind: "tool", text: "Bash: test",
            createdAt: now - 11, toolName: "Bash", capabilities: [command], durationMs: 10000,
            outcome: .success, estimatedContextTokens: 320, callText: "test", resultText: "Passed"))
        entries.append(ActivityEntry(id: "history-edit", kind: "tool", text: "apply_patch: /demo/file-1.swift",
            createdAt: now - 10, toolName: "apply_patch", outcome: .success,
            callText: "Expanded call first line\n" + String(repeating: "Readable source line\n", count: 80) + "Expanded call last line",
            resultText: "Saved the changes", fileChanges: files))
        entries.append(ActivityEntry(id: "history-final", kind: "final", text: "History review finished", createdAt: now))
        return SessionActivity(sessionId: AppModelDemoFixtures.codexSessionId, agent: "codex", state: "idle",
            entries: entries, generatedAt: now, history: .init(cursor: "demo-earlier", hasMore: true))
    }

    static func load(cursor: String, sessionId: String, model: AppModel) -> Bool {
        guard enabled, model.demoMode, cursor == "demo-earlier" else { return false }
        let time = model.activities[sessionId]?.entries.first?.createdAt ?? 1000
        let entries = messages(in: 0..<20, prefix: "Earlier", baseTime: time - 100)
        model.applyActivity(SessionActivity(sessionId: sessionId, agent: "codex", state: "idle", entries: entries,
            generatedAt: Date().timeIntervalSince1970 * 1000,
            history: .init(hasMore: false, requestedCursor: cursor)))
        return true
    }

    private static func messages(in range: Range<Int>, prefix: String, baseTime: Double) -> [ActivityEntry] {
        range.map { index in
            let isUser = index % 4 == 0
            let kind = isUser ? "user" : "message"
            let text = "\(prefix) \(isUser ? "question" : "reply") \(index)"
            return ActivityEntry(id: "history-\(index)", kind: kind, text: text,
                createdAt: baseTime + Double(index))
        }
    }
}
#endif
