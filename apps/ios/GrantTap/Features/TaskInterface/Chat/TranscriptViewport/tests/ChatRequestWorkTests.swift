import XCTest
@testable import GrantTap

final class ChatRequestWorkTests: XCTestCase {
    @MainActor
    func testSelectedRequestKeepsItsFilesAndAgentsAfterTheTaskChangesExecution() {
        let model = AppModel()
        model.demoMode = true
        var mesh = AppModelDemoMeshFixtures.linkedSnapshot(at: 1)
        mesh.executions = ["older", "current"].map {
            .init(taskId: "shared-task", sessionId: $0, provider: "codex", computerId: "computer",
                  workspace: "/repo", startedAt: 1)
        }
        let older = SessionInfo(sessionId: "older", agent: "codex", projectId: mesh.projectId, taskId: "shared-task",
            state: "idle", startedAt: 1, lastActivityAt: 20, tokensSession: 0, tokensLastTurn: 0)
        var current = older.remappingLocalSessionRoot(to: "current")
        current.taskId = "shared-task"
        model.sessions = [older, current]
        model.meshSnapshots = [mesh.projectId: mesh]
        model.activities = ["older": .init(sessionId: "older", agent: "codex", state: "idle", entries: [
            .init(id: "old-request", kind: "user", text: "First execution", createdAt: 1),
            .init(id: "old-edit", kind: "final", text: "Done", createdAt: 2,
                  fileChanges: [.init(path: "older.swift", linesAdded: 1, linesRemoved: 0, diff: "+old")]),
            .init(id: "old-agent", kind: "message", text: "Review", createdAt: 3, childThreadId: "old-reviewer"),
        ], generatedAt: 4), "current": .init(sessionId: "current", agent: "codex", state: "idle", entries: [
            .init(id: "new-request", kind: "user", text: "Next execution", createdAt: 10),
        ], generatedAt: 11)]
        let chat = TaskChatView(session: current, modelOverride: model)
        let prepared = chat.transcriptPresentation
        let work = ChatRequestWork(requestId: "old-request", entries: prepared.sourceEntries,
                                   threads: prepared.childThreads)
        XCTAssertEqual(work.files.map(\.path), ["older.swift"])
        XCTAssertEqual(work.threads.map(\.id), ["old-reviewer"])
        XCTAssertEqual(work.threads.first?.executionSessionId, "older")
        XCTAssertEqual(prepared.requests.request(containing: "old-request")?.id, "old-request")
    }

    func testRailChangesWithSelectedRequestAndKeepsItsAttachmentFragments() {
        let old = RecordedFileChange(path: "old.swift", linesAdded: 4, linesRemoved: 1, diff: "+old")
        let new = RecordedFileChange(path: "new.swift", linesAdded: 9, linesRemoved: 3, diff: "+new")
        let entries: [ActivityEntry] = [
            .init(id: "a", kind: "user", text: "First", createdAt: 10),
            .init(id: "photo", kind: "user", text: "", createdAt: 10, attachments: ["Image"]),
            .init(id: "a-done", kind: "final", text: "Done", createdAt: 20, fileChanges: [old]),
            .init(id: "a-child", kind: "message", text: "Reviewed", createdAt: 21, childThreadId: "reviewer"),
            .init(id: "b", kind: "user", text: "Second", createdAt: 30),
            .init(id: "b-done", kind: "final", text: "Done", createdAt: 40, fileChanges: [new]),
        ]
        let threads = ChildThreadTree.rows(rootId: "root", threads: [
            .init(threadId: "reviewer", parentThreadId: "root", depth: 1, state: "idle",
                  startedAt: 11, lastActivityAt: 21, tokensSession: 0, tokensLastTurn: 0),
            .init(threadId: "builder", parentThreadId: "root", depth: 1, state: "working",
                  startedAt: 31, lastActivityAt: 41, tokensSession: 0, tokensLastTurn: 0),
        ])
        let first = ChatRequestWork(requestId: "a", entries: entries, threads: threads)
        XCTAssertEqual(first.files.map(\.path), ["old.swift"])
        XCTAssertEqual(first.threads.map(\.id), ["reviewer"])
        XCTAssertTrue(first.entries.contains { $0.id == "photo" })
        let second = ChatRequestWork(requestId: "b", entries: entries, threads: threads)
        XCTAssertEqual(second.files.map(\.path), ["new.swift"])
        XCTAssertEqual(second.threads.map(\.id), ["builder"])
        XCTAssertFalse(second.entries.contains { $0.id == "a-child" })
        XCTAssertTrue(ChatRequestWork(requestId: "not-loaded", entries: entries, threads: threads).files.isEmpty)
    }
}
