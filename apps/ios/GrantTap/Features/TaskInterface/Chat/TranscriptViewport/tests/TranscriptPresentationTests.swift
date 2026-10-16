import XCTest
@testable import GrantTap

@MainActor
final class TranscriptPresentationTests: XCTestCase {
    func testCachedPresentationRetainsEveryRowAndRecordedReplyBoundary() {
        let activity = DemoLongTranscript.activity(sessionId: "large", at: 10_000)
        var entries = activity.entries
        entries.append(ActivityEntry(id: "edit", kind: "tool", text: "Saved edit", createdAt: 10_001,
            fileChanges: [.init(path: "source.swift", linesAdded: 3, linesRemoved: 1, diff: "+saved")]))
        entries.append(ActivityEntry(id: "final", kind: "final", text: "Completed", createdAt: 10_002))
        let value = ChatTranscriptPresentation(items: entries.map(CombinedTaskTimelineItem.activity), entries: entries)
        XCTAssertEqual(value.items.count, 5_002)
        XCTAssertEqual(value.rootEntries.count, 5_002)
        XCTAssertEqual(value.rows.first?.id, "activity:long-0")
        XCTAssertEqual(value.rows.last?.id, "activity:final")
        XCTAssertEqual(value.replyChanges["final"], ChatFileChanges.endingAt("final", entries: entries))
        XCTAssertEqual(value.currentFinalId, "final")
        XCTAssertEqual(value.currentFiles, ChatFileChanges.currentReply(entries: entries))
    }

    func testSameIdContentChangesInvalidateOnlyTheirOwnConversationRevision() {
        let model = AppModel()
        model.demoMode = true
        let first = SessionActivity(sessionId: "first", agent: "codex", state: "idle",
            entries: [.init(id: "stable", kind: "message", text: "Earlier", createdAt: 1)], generatedAt: 1)
        model.activities["first"] = first
        let before = model.activityRevisions["first"]
        model.activities["another"] = SessionActivity(sessionId: "another", agent: "codex",
            state: "idle", entries: [], generatedAt: 1)
        XCTAssertEqual(model.activityRevisions["first"], before)
        model.activities["first"] = first
        XCTAssertEqual(model.activityRevisions["first"], before)
        var entry = first.entries[0]
        entry.text = "Completed reply"
        let changed = SessionActivity(sessionId: first.sessionId, agent: first.agent,
                                      state: first.state, entries: [entry], generatedAt: first.generatedAt)
        model.activities["first"] = changed
        XCTAssertEqual(model.activityRevisions["first"], (before ?? 0) + 1)
        model.activities.removeValue(forKey: "first")
        XCTAssertEqual(model.activityRevisions["first"], (before ?? 0) + 2)
    }

    func testOpenedChatIgnoresUnrelatedMeshUpdatesAndObservesItsOwnEvents() {
        let model = AppModel()
        model.demoMode = true
        model.meshSnapshots = [:]
        model.pendingMeshEvents = []
        let session = SessionInfo(sessionId: "scoped-chat", agent: "codex", taskId: "chosen-task",
            title: "Scoped chat", cwd: nil, branch: nil, model: nil, state: "idle",
            startedAt: 1, lastActivityAt: 1, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        let chat = TaskChatView(session: session, modelOverride: model)
        let before = chat.transcriptRevision
        var snapshot = AppModelDemoMeshFixtures.linkedSnapshot(at: 1)
        snapshot.events = [meshEvent(taskId: "another-task", summary: "Other task changed")]
        model.meshSnapshots[snapshot.projectId] = snapshot
        model.pendingMeshEvents = snapshot.events
        XCTAssertEqual(chat.transcriptRevision, before,
                       "Unrelated Mesh traffic must not rebuild a long opened transcript.")
        snapshot.events = [meshEvent(taskId: "chosen-task", summary: "Current task changed")]
        model.meshSnapshots[snapshot.projectId] = snapshot
        let ownEvent = chat.transcriptRevision
        XCTAssertNotEqual(ownEvent, before)
        snapshot.events = [meshEvent(taskId: "chosen-task", summary: "Updated same event")]
        model.meshSnapshots[snapshot.projectId] = snapshot
        XCTAssertNotEqual(chat.transcriptRevision, ownEvent,
                          "A changed payload must be visible even when the event id is unchanged.")
    }

    private func meshEvent(taskId: String, summary: String) -> ProjectMeshEvent {
        ProjectMeshEvent(type: "mesh.event", sessionId: "scoped-chat", eventId: "stable-event",
            projectId: AppModelDemoMeshFixtures.linkedProjectId, taskId: taskId,
            sourceSessionId: "scoped-chat", eventType: "STATUS", createdAt: 1,
            payload: .init(summary: summary))
    }
}
