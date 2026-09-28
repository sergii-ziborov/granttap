import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class TranscriptHistoryTests: XCTestCase {
    func testOlderPageSurvivesNewerLiveSnapshotAndMemoryWindow() {
        let recent = (40..<350).map { ActivityEntry(id: "row-\($0)", kind: "message", text: "Recent", createdAt: Double($0)) }
        let older = (0..<40).map { ActivityEntry(id: "row-\($0)", kind: "user", text: "Earlier question", createdAt: Double($0)) }
        let live = SessionActivity(sessionId: "s", agent: "codex", state: "working", entries: recent, generatedAt: 10)
        let old = SessionActivity(sessionId: "s", agent: "codex", state: "idle", entries: older, generatedAt: 9,
                                  history: .init(cursor: "older", hasMore: true, requestedCursor: "page"))
        let merged = AppModel.mergeActivity(existing: live, incoming: old)
        XCTAssertEqual(merged.entries.count, 350)
        XCTAssertEqual(merged.entries.first?.id, "row-0")
        XCTAssertEqual(merged.entries.last?.id, "row-349")
        XCTAssertEqual(merged.state, "working")
        let refresh = SessionActivity(sessionId: "s", agent: "codex", state: "working", entries: recent,
                                      generatedAt: 11, history: .init(cursor: "latest-page", hasMore: true))
        let updated = AppModel.mergeActivity(existing: merged, incoming: refresh)
        XCTAssertEqual(updated.history?.cursor, "older")
        XCTAssertEqual(updated.entries.count, 350)
        XCTAssertNil(SessionActivityPersistence.bounded(["s": updated])["s"]?.history)
        let model = AppModel()
        model.activities["s"] = updated
        model.releaseTranscriptHistory(sessionId: "s")
        XCTAssertEqual(model.activities["s"]?.entries.count, 312)
        XCTAssertEqual(model.activities["s"]?.entries.first?.id, "row-38")
        XCTAssertNil(model.activities["s"]?.history)
    }

    func testFileSummaryBelongsToItsUserTurnAndKeepsFullPaths() {
        let old = RecordedFileChange(path: "/older/a.swift", linesAdded: 9, linesRemoved: 3, diff: "+older")
        let first = RecordedFileChange(path: "/one/a.swift", linesAdded: 2, linesRemoved: 1, diff: "-old\n+new")
        let next = RecordedFileChange(path: "/one/a.swift", linesAdded: 1, linesRemoved: 0, diff: "+extra")
        let other = RecordedFileChange(path: "/two/a.swift", linesAdded: 3, linesRemoved: 0, diff: "+different")
        let entries = [ActivityEntry(id: "old", kind: "tool", text: "Old edits", createdAt: 1, fileChanges: [old]),
            ActivityEntry(id: "user", kind: "user", text: "Current request", createdAt: 2),
            ActivityEntry(id: "edit-1", kind: "tool", text: "Edit", createdAt: 3, fileChanges: [first]),
            ActivityEntry(id: "edit-2", kind: "tool", text: "Edit", createdAt: 4, fileChanges: [next, other]),
            ActivityEntry(id: "final", kind: "final", text: "Done", createdAt: 5)]
        let files = ChatFileChanges.endingAt("final", entries: entries)
        XCTAssertEqual(files.map(\.path), ["/one/a.swift", "/two/a.swift"])
        XCTAssertEqual(files.first?.linesAdded, 3)
        XCTAssertEqual(files.first?.linesRemoved, 1)
        XCTAssertTrue(files.first?.diff.contains("+extra") == true)
        XCTAssertEqual(ChatFileChanges.endingAt("missing", entries: entries), [])
        render(ChatFileChangesCard(files: files, expanded: true))
        let reported = ActivityEntry(id: "summary", kind: "final", text: "Done", createdAt: 6,
                                     fileChanges: [other], fileChangesComplete: true)
        XCTAssertEqual(ChatFileChanges.endingAt("summary", entries: entries + [reported]), [other])
        let many = (1...4).map { RecordedFileChange(path: "/repo/file-\($0).swift", linesAdded: 1,
                                                   linesRemoved: 0, diff: "+new", diffTruncated: true) }
        render(ChatFileChangesCard(files: many, complete: false))
    }

    func testWireDetailsKeepNewlinesAndHistoryMetadata() throws {
        let entry = ActivityEntry(id: "call", kind: "tool", text: "Short label", createdAt: 2,
            callText: "First line\n" + String(repeating: "Detailed source\n", count: 80) + "Last line",
            resultText: "Completed\nRecorded result", detailTruncated: false)
        let image = ActivityEntry(id: "image", kind: "user", text: "", createdAt: 1, attachments: ["Image"])
        let activity = SessionActivity(sessionId: "s", agent: "codex", state: "idle", entries: [entry, image], generatedAt: 3,
            history: .init(cursor: "earlier", hasMore: true))
        let decoded = try JSONDecoder().decode(SessionActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(decoded, activity)
        XCTAssertTrue(decoded.entries[0].callText?.hasSuffix("Last line") == true)
        render(ActivityStepDetail(step: ActivityStep(entry: decoded.entries[0]), accent: .blue))
        render(DiffPreviewView(text: "@@\n-old\n+new\n context", wrapLines: false))
        for outcome in CapabilityOutcome.allCases {
            var variant = entry
            variant.outcome = outcome
            variant.detailTruncated = true
            variant.diffPreview = "+new"
            render(ActivityStepDetail(step: ActivityStep(entry: variant), accent: .blue))
        }
    }

    func testSameTimestampOlderPageStaysBeforeLiveEntries() {
        let entry: (String) -> ActivityEntry = { ActivityEntry(id: $0, kind: "message", text: $0, createdAt: 1) }
        let live = SessionActivity(sessionId: "s", agent: "codex", state: "idle", entries: [entry("a"), entry("b")], generatedAt: 2)
        let old = SessionActivity(sessionId: "s", agent: "codex", state: "idle", entries: [entry("z"), entry("y")], generatedAt: 3,
                                  history: .init(hasMore: false, requestedCursor: "page"))
        XCTAssertEqual(AppModel.mergeActivity(existing: live, incoming: old).entries.map(\.id), ["z", "y", "a", "b"])
    }

    func testNativePagesReplaceLegacyCacheIdsWithoutDroppingRepeatedQuestions() {
        let old = ActivityEntry(id: "s:100:501", kind: "user", text: "Continue", createdAt: 100)
        let answer = ActivityEntry(id: "s:101:602", kind: "message", text: "Done", createdAt: 101)
        let pending = ActivityEntry(id: "local-user-pending", kind: "user", text: "Continue", createdAt: 102)
        let earlier = ActivityEntry(id: "s:90:300", kind: "user", text: "Earlier", createdAt: 90)
        let native = ActivityEntry(id: "s:100:0123456789abcdef:1", kind: "user", text: "Continue", createdAt: 100)
        let final = ActivityEntry(id: "s:101:abcdef0123456789:2", kind: "final", text: "Done", createdAt: 101)
        let repeated = ActivityEntry(id: "s:103:fedcba9876543210:1", kind: "user", text: "Continue", createdAt: 103)
        let live = SessionActivity(sessionId: "s", agent: "codex", state: "working",
            entries: [earlier, old, answer, pending], generatedAt: 105)
        let page = SessionActivity(sessionId: "s", agent: "codex", state: "working",
            entries: [native, final, repeated], generatedAt: 106, history: .init(cursor: "older", hasMore: true))
        let merged = AppModel.mergeActivity(existing: live, incoming: page)
        XCTAssertEqual(merged.entries.map(\.id), [earlier.id, native.id, final.id, pending.id, repeated.id])
        XCTAssertEqual(merged.entries.filter { $0.text == "Continue" }.count, 3)
        XCTAssertEqual(merged.entries.filter { $0.text == "Done" }.count, 1)
    }

    func testTaskTimelineKeepsProviderOrderAtSameTimestamp() {
        let session = SessionInfo(sessionId: "same-time", agent: "codex", title: "History", cwd: "/repo",
            state: "idle", startedAt: 1, lastActivityAt: 10, tokensSession: 0, tokensLastTurn: 0)
        let entries = (0..<32).map {
            ActivityEntry(id: "native-block-\($0)", kind: "message", text: "Block \($0)", createdAt: 10)
        }
        let model = AppModel()
        model.activities[session.sessionId] = SessionActivity(sessionId: session.sessionId, agent: "codex",
            state: "idle", entries: entries, generatedAt: 10)
        let view = TaskChatView(session: session, modelOverride: model)
        XCTAssertEqual(view.taskActivityEntries.map(\.id), entries.map(\.id))
        let ids = view.combinedTimeline.compactMap { item -> String? in
            if case .activity(let entry) = item { return entry.id }
            return nil
        }
        XCTAssertEqual(ids, entries.map(\.id))
    }

    func testClaudeNativeIdentityMigratesLegacyRowsOneForOne() {
        let old = (0..<2).map { ActivityEntry(id: "s:100:\($0)", kind: "user", text: "Continue", createdAt: 100) }
        let native = (0..<2).map { ActivityEntry(id: "s:message:" + String(repeating: String($0), count: 24) + ":0",
            kind: "user", text: "Continue", createdAt: 100) }
        let pending = ActivityEntry(id: "local-user-pending", kind: "user", text: "Continue", createdAt: 100)
        let existing = SessionActivity(sessionId: "s", agent: "claude", state: "idle", entries: old + [pending], generatedAt: 100)
        let page = SessionActivity(sessionId: "s", agent: "claude", state: "idle", entries: native, generatedAt: 101,
            history: .init(hasMore: false))
        let merged = AppModel.mergeActivity(existing: existing, incoming: page)
        XCTAssertEqual(merged.entries.map(\.id), [pending.id] + native.map(\.id))
        XCTAssertEqual(AppModel.mergeActivity(existing: merged, incoming: page).entries, merged.entries)
    }

    private func render<Content: View>(_ content: Content) {
        let host = UIHostingController(rootView: NavigationView { content })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1000))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }
}
