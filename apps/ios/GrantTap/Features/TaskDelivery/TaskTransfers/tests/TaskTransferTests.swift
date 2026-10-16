import XCTest
@testable import GrantTap

@MainActor
final class TaskTransferTests: XCTestCase {
    private let notice = TaskTransferNotice(sourceSessionId: "source", targetSessionId: "destination",
        projectId: "project", taskId: "task", capsuleHash: String(repeating: "a", count: 64), acceptedAt: 10)

    func testCatalogDecodingRetainsTheTransferredTaskWarning() throws {
        let data = try JSONSerialization.data(withJSONObject: ["sessionId": "source", "agent": "codex",
            "projectId": "project", "taskId": "task", "state": "idle", "startedAt": 1,
            "lastActivityAt": 2, "tokensSession": 0, "tokensLastTurn": 0, "effort": "high",
            "transfer": ["sourceSessionId": "source", "targetSessionId": "destination", "projectId": "project",
                         "taskId": "task", "capsuleHash": notice.capsuleHash, "acceptedAt": 10]])
        let chat = try JSONDecoder().decode(SessionInfo.self, from: data)
        XCTAssertEqual(chat.transfer?.targetSessionId, "destination")
        XCTAssertEqual(chat.transfer?.capsuleHash, notice.capsuleHash)
        XCTAssertEqual(chat.effort, "high")
    }

    private func fixture() -> (AppModel, TaskTransferContinue, SessionInfo) {
        let pairing = Pairing(relayUrl: "wss://relay.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture", myPublicKey: "", mySecretKey: "",
            peerPublicKey: "", pushAuth: String(repeating: "b", count: 64))
        let model = AppModel()
        model.demoMode = true
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.sessionSourceRooms = ["source": [pairing.room]]
        model.taskTransfers = TaskTransferProgress()
        let command = TaskTransferContinue(sessionId: "source", projectId: "project", taskId: "task",
            capsuleHash: notice.capsuleHash, requestId: "request", createdAt: 20)
        model.taskTransfers.pending["source"] = command
        let chat = SessionInfo(sessionId: "source", agent: "codex", projectId: "project", taskId: "task",
            transfer: notice, state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [chat]
        return (model, command, chat)
    }

    private func result(_ notice: TaskTransferNotice, requestId: String = "request") -> TaskTransferContinueResult {
        .init(sessionId: "source", projectId: "project", taskId: "task", capsuleHash: self.notice.capsuleHash,
              requestId: requestId, accepted: true, notice: notice)
    }

    func testOnlyTheOwningComputerAndExactRequestMayConfirmContinuation() {
        let (model, _, chat) = fixture()
        var confirmed = notice
        confirmed.continuedAt = 30
        model.receive(result(confirmed), fromRoom: "foreign")
        model.receive(result(confirmed, requestId: "older"), fromRoom: String(repeating: "a", count: 32))
        XCTAssertNotNil(model.taskTransfers.pending["source"])
        XCTAssertNil(model.transferNotice(for: chat)?.continuedAt)
        model.receive(result(confirmed), fromRoom: String(repeating: "a", count: 32))
        XCTAssertNil(model.taskTransfers.pending["source"])
        XCTAssertEqual(model.transferNotice(for: chat)?.continuedAt, 30)
        XCTAssertNil(model.taskTransfers.confirmed["destination"])
    }

    func testMalformedConfirmationCannotRemoveTheTransferredWarning() {
        let (model, _, chat) = fixture()
        var invalid = notice
        invalid.continuedAt = 0
        model.receive(result(invalid), fromRoom: String(repeating: "a", count: 32))
        XCTAssertNil(model.transferNotice(for: chat)?.continuedAt)
        XCTAssertNotNil(model.taskTransfers.errors["source"])
    }

    func testAConfirmationForAnotherDestinationCannotReopenThisSource() {
        let (model, _, chat) = fixture()
        let wrong = TaskTransferNotice(sourceSessionId: "source", targetSessionId: "another",
            projectId: "project", taskId: "task", capsuleHash: notice.capsuleHash,
            acceptedAt: 10, continuedAt: 30)
        model.receive(result(wrong), fromRoom: String(repeating: "a", count: 32))
        XCTAssertNil(model.transferNotice(for: chat)?.continuedAt)
        XCTAssertNotNil(model.taskTransfers.errors["source"])
    }

    func testPendingTransferHasNoInventedDestinationAndKeepsExplicitParallelConsentAfterConfirmation() throws {
        let (model, _, original) = fixture()
        let pendingData = try JSONSerialization.data(withJSONObject: [
            "sourceSessionId": "source", "projectId": "project", "taskId": "task",
            "capsuleHash": notice.capsuleHash, "phase": "pending", "queuedAt": 10,
            "targetComputerId": "target-computer", "targetProvider": "grok"
        ])
        var pending = try JSONDecoder().decode(TaskTransferNotice.self, from: pendingData)
        var chat = original
        chat.transfer = pending
        model.sessions = [chat]
        XCTAssertNil(model.transferNotice(for: chat)?.targetSessionId)
        pending.continuedAt = 30
        model.receive(result(pending), fromRoom: String(repeating: "a", count: 32))
        XCTAssertEqual(model.transferNotice(for: chat)?.continuedAt, 30)
        chat.transfer = notice
        model.sessions = [chat]
        XCTAssertEqual(model.transferNotice(for: chat)?.targetSessionId, "destination")
        XCTAssertEqual(model.transferNotice(for: chat)?.continuedAt, 30)
    }
}
