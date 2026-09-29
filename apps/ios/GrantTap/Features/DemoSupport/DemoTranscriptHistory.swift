#if DEBUG
import Foundation

@MainActor
enum DemoTranscriptHistory {
    static var enabled: Bool { ProcessInfo.processInfo.environment["GRANTTAP_TEST_TRANSCRIPT_HISTORY"] == "1" }

    static func initial(at now: Double) -> SessionActivity {
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_PINNED_SCROLL"] == "1" {
            return readingFixture(at: now)
        }
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
        if requestNavigationEnabled { entries.removeAll { $0.id.hasPrefix("history-") && Int($0.id.dropFirst(8)) != nil } }
        return SessionActivity(sessionId: AppModelDemoFixtures.codexSessionId, agent: "codex", state: "idle",
            entries: entries, generatedAt: now,
            history: .init(cursor: requestNavigationEnabled ? "requests-latest" : "demo-earlier", hasMore: true))
    }

    static func load(cursor: String, sessionId: String, model: AppModel) -> Bool {
        guard enabled, model.demoMode else { return false }
        if requestNavigationEnabled { return loadRequestPage(cursor, sessionId: sessionId, model: model) }
        guard cursor == "demo-earlier" else { return false }
        let time = model.activities[sessionId]?.entries.first?.createdAt ?? 1000
        let entries = messages(in: 0..<20, prefix: "Earlier", baseTime: time - 100)
        model.applyActivity(SessionActivity(sessionId: sessionId, agent: "codex", state: "idle", entries: entries,
            generatedAt: Date().timeIntervalSince1970 * 1000,
            history: .init(hasMore: false, requestedCursor: cursor)))
        return true
    }

    private static var requestNavigationEnabled: Bool {
        ProcessInfo.processInfo.environment["GRANTTAP_TEST_REQUEST_NAVIGATION"] == "1"
    }

    private static func loadRequestPage(_ cursor: String, sessionId: String, model: AppModel) -> Bool {
        let pages = ["requests-latest", "requests-previous", "requests-first"]
        guard let index = pages.firstIndex(of: cursor) else { return false }
        let at = (model.activities[sessionId]?.entries.first?.createdAt ?? 1000) - 50
        let name = ["Latest user request", "Previous user request", "First user request"][index]
        let entry = ActivityEntry(id: "request-\(index)", kind: "user", text: name, createdAt: at)
        let more = index + 1 < pages.count
        model.applyActivity(SessionActivity(sessionId: sessionId, agent: "codex", state: "idle",
            entries: [entry, ActivityEntry(id: "request-\(index)-image", kind: "user", text: "",
                createdAt: at, attachments: ["Image"])], generatedAt: Date().timeIntervalSince1970 * 1000,
            history: .init(cursor: more ? pages[index + 1] : nil, hasMore: more, requestedCursor: cursor)))
        return true
    }

    private static func readingFixture(at now: Double) -> SessionActivity {
        let names = ["First viewport request", "Second viewport request", "Third viewport request"]
        let entries = names.enumerated().flatMap { index, name -> [ActivityEntry] in
            let time = now - 1000 + Double(index * 100)
            return [ActivityEntry(id: "viewport-request-\(index)", kind: "user", text: name, createdAt: time),
                ActivityEntry(id: "viewport-image-\(index)", kind: "user", text: "", createdAt: time,
                    attachments: ["Image"])] + (0..<8).map { reply in
                ActivityEntry(id: "viewport-reply-\(index)-\(reply)", kind: "message",
                    text: "Reply \(index).\(reply)\n" + String(repeating: "A fixture transcript line for scroll navigation.\n", count: 6),
                    createdAt: time + Double(reply + 1))
            }
        }
        return SessionActivity(sessionId: AppModelDemoFixtures.codexSessionId, agent: "codex", state: "idle",
            entries: entries, generatedAt: now, history: .init(hasMore: false))
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
