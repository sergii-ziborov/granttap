import XCTest
@testable import GrantTap

@MainActor
final class ApprovalDeliveryIntegrationTests: XCTestCase {
    private func model() -> AppModel {
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "approval-test", role: "phone",
            deviceName: "Test", senderId: "test-controller",
            myPublicKey: Data(repeating: 1, count: 32).base64EncodedString(),
            mySecretKey: Data(repeating: 2, count: 32).base64EncodedString(),
            peerPublicKey: Data(repeating: 3, count: 32).base64EncodedString())
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.relaysByRoom = [pairing.room: RelayClient(pairing: pairing)]
        model.sessions = []; model.sessionHistory = []; model.sessionSourceRooms = [:]
        model.approvalDecisionQueue = ApprovalDecisionQueue(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("decisions.json"))
        return model
    }

    private func request() -> ApprovalRequest {
        .init(type: "approval.request", requestId: UUID().uuidString, agent: "claude", kind: "tool",
              tool: "Edit", title: "Edit", command: nil, cwd: "/test/project", sessionId: UUID().uuidString,
              risk: .medium, danger: nil, createdAt: Date().timeIntervalSince1970 * 1_000)
    }

    func testApprovalMakesItsChatAvailableAndOfflineDecisionWaitsForExactNativeConfirmation() {
        let savedCatalog = SessionCatalogCache.load()
        defer {
            if let savedCatalog { SessionCatalogCache.save(savedCatalog, retainingPreviousHistory: false) }
            else { SessionCatalogCache.clear() }
        }
        let model = model(), request = request()
        model.receive(request, fromRoom: "approval-test")
        XCTAssertEqual(model.sessions.first?.sessionId, request.sessionId)
        XCTAssertEqual(model.sessions.first?.state, "waiting")
        XCTAssertEqual(model.approvalChatId(request), request.sessionId)
        XCTAssertGreaterThan(model.roomRuntime["approval-test"]?.lastHeartbeatAt ?? 0, 0)
        RenderProbe.render(ApprovalChatControls(request: request).environmentObject(model))
        model.decide(request, "allow")
        XCTAssertEqual(model.approvalDecisionsInFlight[request.requestId], "allow")
        XCTAssertEqual(model.approvalDecisionQueue.entries.count, 1)
        XCTAssertEqual(model.approvalDecisionDeliveryMessage(request),
                       L("Saving decision on relay…"))
        model.noteApprovalDecisionSent(request.requestId, sessionId: request.sessionId, succeeded: true)
        XCTAssertEqual(model.approvalDecisionDeliveryMessage(request), L("Decision saved on relay"))
        XCTAssertEqual(model.approvalDecisionQueue.entries.count, 1)
        model.receive(.init(type: "approval.resolved", requestId: request.requestId,
            status: "applied", decision: "allow", sessionId: "wrong", resolvedAt: 1), fromRoom: "approval-test")
        XCTAssertEqual(model.approvalDecisionQueue.entries.count, 1)
        model.receive(.init(type: "approval.resolved", requestId: request.requestId,
            status: "applied", decision: "allow", sessionId: request.sessionId, resolvedAt: 1), fromRoom: "approval-test")
        XCTAssertTrue(model.approvalDecisionQueue.entries.isEmpty)
        XCTAssertNil(model.approvalDecisionsInFlight[request.requestId])
        XCTAssertTrue(model.pending.isEmpty)
    }

    func testOldOrFuturePublicationsCannotMakeOfflineComputerLive() {
        let model = model(), now = Date().timeIntervalSince1970 * 1_000
        model.noteAuthenticatedMachineActivity(fromRoom: "approval-test", generatedAt: now - 100_000)
        model.noteAuthenticatedMachineActivity(fromRoom: "approval-test", generatedAt: now + 40_000)
        XCTAssertNil(model.roomRuntime["approval-test"])
        model.noteAuthenticatedMachineActivity(fromRoom: "approval-test", generatedAt: now)
        XCTAssertGreaterThan(model.roomRuntime["approval-test"]?.lastHeartbeatAt ?? 0, 0)
    }

    func testCancelAllCoversSavedDecisionsEvenWhenVisibleCardsWereLostOnRestart() {
        let model = model(), request = request()
        XCTAssertTrue(model.approvalDecisionQueue.enqueue(.init(requestId: request.requestId,
            roomId: "approval-test", sessionId: request.sessionId, decision: "deny", by: "phone", createdAt: 1)))
        XCTAssertTrue(model.pending.isEmpty)
        model.clearAllPendingApprovals(reason: "unscoped legacy cancellation", fromRoom: nil)
        XCTAssertEqual(model.approvalDecisionQueue.entries.count, 1)
        model.clearAllPendingApprovals(reason: "native cancellation", fromRoom: "other-computer")
        XCTAssertEqual(model.approvalDecisionQueue.entries.count, 1)
        model.clearAllPendingApprovals(reason: "native cancellation", fromRoom: "approval-test")
        XCTAssertTrue(model.approvalDecisionQueue.entries.isEmpty)
        XCTAssertTrue(model.wasApprovalTerminal(request.requestId, room: "approval-test", sessionId: request.sessionId))
    }
}
