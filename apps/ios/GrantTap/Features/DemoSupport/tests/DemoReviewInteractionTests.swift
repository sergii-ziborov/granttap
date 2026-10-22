import XCTest
@testable import GrantTap

@MainActor
final class DemoReviewInteractionTests: XCTestCase {
    func testSampleApprovalResolvesLocallyAndCanBeReset() throws {
        let model = AppModel()
        model.startDemo()
        let request = try XCTUnwrap(model.pending.first)
        let queued = model.approvalDecisionQueue.entries

        model.decide(request, "deny")

        XCTAssertFalse(model.pending.contains { $0.requestId == request.requestId })
        XCTAssertNil(model.approvalDecisionsInFlight[request.requestId])
        XCTAssertEqual(model.approvalDecisionQueue.entries, queued)
        XCTAssertEqual(ApprovalDecisionQueue().entries, queued)
        XCTAssertTrue(model.activities[AppModelDemoFixtures.codexSessionId]?.entries
            .contains { $0.text.contains(L("Demo decision saved. No command was executed.")) } == true)
        model.startDemo()
        XCTAssertTrue(model.pending.contains { $0.requestId == request.requestId })
    }

    func testSampleChatAndQuestionNeverEnterTheDurableOutbox() throws {
        let model = AppModel()
        model.startDemo()
        let count = model.deliveries.count
        let persistedIds = DeliveryPersistence.load().map(\.id)
        let session = AppModelDemoFixtures.codexSessionId
        model.sendMessage("Review sample", sessionId: session)

        XCTAssertEqual(model.deliveries.count, count)
        XCTAssertEqual(DeliveryPersistence.load().map(\.id), persistedIds)
        XCTAssertTrue(model.activities[session]?.entries.contains { $0.text == "Review sample" } == true)
        XCTAssertTrue(model.activities[session]?.entries.contains {
            $0.text == L("Demo reply received. No message was sent to a computer.")
        } == true)
        let question = try XCTUnwrap(model.questions.first)
        model.answerQuestion(try XCTUnwrap(question.requestId), "Yes")
        XCTAssertFalse(model.questions.contains { $0.requestId == question.requestId })
        XCTAssertEqual(model.deliveries.count, count)
        XCTAssertEqual(DeliveryPersistence.load().map(\.id), persistedIds)
    }

    func testDemoDoesNotSubmitRequestsForAnUnrelatedSession() {
        let model = AppModel()
        model.startDemo()
        let deliveries = model.deliveries.count
        model.sendMessage("Must stay local", sessionId: "unrelated-session")
        XCTAssertEqual(model.deliveries.count, deliveries)
        XCTAssertNil(model.activities["unrelated-session"])
    }

    func testDemoIgnoresInvalidAndRepeatedDecisionsAndCrossSessionReplies() throws {
        let model = AppModel()
        model.startDemo()
        let request = try XCTUnwrap(model.pending.first)
        model.decide(request, "unknown")
        XCTAssertTrue(model.pending.contains { $0.requestId == request.requestId })
        model.decide(request, "allow")
        let entries = model.activities[AppModelDemoFixtures.codexSessionId]?.entries.count
        model.decide(request, "allow")
        XCTAssertEqual(model.activities[AppModelDemoFixtures.codexSessionId]?.entries.count, entries)
        let question = try XCTUnwrap(model.questions.first)
        model.sendMessage("Wrong chat", sessionId: AppModelDemoFixtures.claudeSessionId,
                          requestId: question.requestId)
        XCTAssertTrue(model.questions.contains { $0.requestId == question.requestId })
        model.sendMessage("   ", sessionId: AppModelDemoFixtures.codexSessionId)
        XCTAssertEqual(model.activities[AppModelDemoFixtures.codexSessionId]?.entries.count, entries)
        model.sendMessage("Default sample chat")
        XCTAssertTrue(model.activities[AppModelDemoFixtures.codexSessionId]?.entries.contains {
            $0.text == "Default sample chat"
        } == true)
    }

    func testQueuedSamplesAreRemovedOnExitWithoutRemovingRealPendingMessages() throws {
        let original = DeliveryPersistence.load()
        defer { DeliveryPersistence.save(original) }
        let model = AppModel()
        model.deliveries = []
        let real = SessionInfo(sessionId: "review-existing-live-task", agent: "codex", state: "working",
            startedAt: 1, lastActivityAt: 1, tokensSession: 0, tokensLastTurn: 0)
        XCTAssertTrue(model.queueChatMessage("Existing live message", to: real))
        model.startDemo()
        let sample = try XCTUnwrap(model.sessions.first)
        XCTAssertTrue(model.queueChatMessage("Sample only", to: sample))

        model.stopDemo()
        XCTAssertTrue(model.queueChatMessage("Next live message", to: real))

        XCTAssertEqual(model.deliveries.count, 2)
        XCTAssertEqual(Set(model.deliveries.compactMap(\.sessionId)), [real.sessionId])
        let persisted = DeliveryPersistence.load()
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.contains { $0.text == "Existing live message" })
        XCTAssertFalse(persisted.contains { $0.text == "Sample only" })
    }
}
