import XCTest
@testable import GrantTap

final class ApprovalDecisionQueueTests: XCTestCase {
    private func storage() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("decisions.json")
    }

    private func entry(_ id: String = "request", room: String = "computer", session: String? = "chat")
        -> ApprovalDecisionQueue.Entry {
        .init(requestId: id, roomId: room, sessionId: session,
              decision: "allow", by: "phone", createdAt: 1)
    }

    func testDecisionSurvivesRestartAndRequiresExactComputerAndChat() throws {
        let url = storage()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = ApprovalDecisionQueue(url: url), action = entry()
        XCTAssertTrue(queue.enqueue(action))
        XCTAssertTrue(queue.enqueue(action))
        XCTAssertFalse(queue.enqueue(entry(room: "other")))
        XCTAssertNil(queue.entry("request", roomId: "other", sessionId: "chat"))
        XCTAssertNil(queue.entry("request", roomId: "computer", sessionId: "other"))
        queue.markSent(action, at: 10)
        let reopened = ApprovalDecisionQueue(url: url)
        XCTAssertEqual(reopened.entry("request", roomId: "computer", sessionId: "chat")?.sentAt, 10)
        reopened.markSent(action, at: nil)
        XCTAssertNil(ApprovalDecisionQueue(url: url).entries.first?.sentAt)
        reopened.remove("request", roomId: "other", sessionId: "chat")
        XCTAssertEqual(reopened.entries.count, 1)
        reopened.remove("request", roomId: "computer", sessionId: "chat")
        XCTAssertTrue(ApprovalDecisionQueue(url: url).entries.isEmpty)
    }

    func testQuestionAnswersSurviveOfflineRestartWithTheirExactChat() throws {
        let url = storage()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = ApprovalDecisionQueue(url: url)
        var decision = entry()
        decision.note = "{\"Which platform?\":\"Website\"}"
        XCTAssertTrue(queue.enqueue(decision))
        let saved = ApprovalDecisionQueue(url: url).entry("request", roomId: "computer", sessionId: "chat")
        XCTAssertEqual(saved?.note, decision.note)
        XCTAssertNil(saved?.sentAt)
        XCTAssertNil(ApprovalDecisionQueue(url: url).entry("request", roomId: "other", sessionId: "chat"))
        let payload = Payloads.decision("request", "allow", by: "phone", sessionId: "chat", note: saved?.note)
        XCTAssertEqual(payload.note, decision.note)
    }

    func testUnlinkAndStorageAdmissionPreserveOtherComputerDecisions() throws {
        let url = storage()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = ApprovalDecisionQueue(url: url)
        for index in 0..<128 { XCTAssertTrue(queue.enqueue(entry("r-\(index)", room: index == 0 ? "A" : "B"))) }
        XCTAssertFalse(queue.enqueue(entry("overflow")))
        XCTAssertEqual(queue.entries.count, 128)
        queue.removeRoom("A")
        XCTAssertEqual(ApprovalDecisionQueue(url: url).entries.count, 127)
        queue.markSent(entry("missing"), at: 1)
        XCTAssertEqual(queue.entries.count, 127)
        XCTAssertFalse(queue.enqueue(entry("empty", room: "")))
        var invalid = entry("invalid")
        invalid = .init(requestId: invalid.requestId, roomId: invalid.roomId, sessionId: nil,
                        decision: "unexpected", by: "phone", createdAt: 1)
        XCTAssertFalse(queue.enqueue(invalid))
        let blocked = url.deletingLastPathComponent().appendingPathComponent("file")
        try Data().write(to: blocked)
        XCTAssertFalse(ApprovalDecisionQueue(url: blocked.appendingPathComponent("child")).enqueue(entry()))
        try Data("invalid JSON".utf8).write(to: url)
        XCTAssertTrue(ApprovalDecisionQueue(url: url).entries.isEmpty)
    }
}
