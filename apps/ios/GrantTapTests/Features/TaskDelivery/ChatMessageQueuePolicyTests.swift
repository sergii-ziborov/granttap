import XCTest
@testable import GrantTap

final class ChatMessageQueuePolicyTests: XCTestCase {
    private func row(_ id: String, at time: Double = 1, state: DeliveryState = .queued,
                     waiting: Bool = true, room: String = "room-a") -> OutgoingDelivery {
        OutgoingDelivery(id: id, text: "Next", agent: "codex", cwd: nil,
            sessionId: "session", requestId: nil, roomId: room, attachments: [],
            preferredMcp: nil, skill: nil, projectId: "project",
            createdAt: time, updatedAt: time, attempts: waiting ? 0 : 1,
            state: state, error: nil, nextRetryAt: nil,
            chatQueue: ChatMessageQueueContext(waiting: waiting, transport: .relay, taskId: "task"))
    }

    private func session(_ state: String = "idle", agent: String = "codex") -> SessionInfo {
        SessionInfo(sessionId: "session", agent: agent, projectId: "project", taskId: "task",
                    state: state, startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
    }

    func testFIFOReleasesOnePerChatAndKeepsIndependentRoomsSeparate() {
        let first = row("first", at: 1)
        let second = row("second", at: 2)
        let other = row("other", at: 3, room: "room-b")
        XCTAssertEqual(ChatMessageQueuePolicy.ready([second, other, first], observed: [session()]),
                       ["first", "other"])
        XCTAssertFalse(ChatMessageQueuePolicy.sameChat(first, other))
    }

    func testBusyPausedUnknownAndChangedExecutionNeverAutoSend() {
        let held = row("held")
        for state in ["working", "needs_you", "unknown", "blocked"] {
            XCTAssertTrue(ChatMessageQueuePolicy.ready([held], observed: [session(state)]).isEmpty)
        }
        var paused = session()
        paused.paused = true
        XCTAssertTrue(ChatMessageQueuePolicy.ready([held], observed: [paused]).isEmpty)
        var changed = session(agent: "claude")
        XCTAssertTrue(ChatMessageQueuePolicy.ready([held], observed: [changed]).isEmpty)
        changed = session()
        changed.projectId = "different"
        XCTAssertTrue(ChatMessageQueuePolicy.ready([held], observed: [changed]).isEmpty)
        changed = session()
        changed.taskId = "different"
        XCTAssertTrue(ChatMessageQueuePolicy.ready([held], observed: [changed]).isEmpty)
        XCTAssertTrue(ChatMessageQueuePolicy.ready([held], observed: []).isEmpty)
    }

    func testActiveOrFailedMessageBlocksTheNextEvenAfterSendNowOutOfOrder() {
        let held = row("first", at: 1)
        for state in [DeliveryState.sending, .queued, .failed] {
            let sentNow = row("later", at: 2, state: state, waiting: false)
            XCTAssertTrue(ChatMessageQueuePolicy.ready([held, sentNow], observed: [session()]).isEmpty)
        }
        let completed = row("later", at: 2, state: .delivered, waiting: false)
        XCTAssertEqual(ChatMessageQueuePolicy.ready([held, completed], observed: [session("finished")]),
                       [held.id])
    }

    func testEqualTimestampsUseStableIDsAndLegacyRowsAreNotHeld() {
        XCTAssertEqual(ChatMessageQueuePolicy.ready([row("b"), row("a")], observed: [session()]), ["a"])
        var legacy = row("legacy")
        legacy.chatQueue = nil
        XCTAssertFalse(ChatMessageQueuePolicy.canCancel(legacy))
        XCTAssertTrue(ChatMessageQueuePolicy.ready([legacy], observed: [session()]).isEmpty)
        var rejected = row("rejected")
        rejected.admissionRejected = true
        XCTAssertFalse(ChatMessageQueuePolicy.canCancel(rejected))
        XCTAssertTrue(ChatMessageQueuePolicy.ready([rejected], observed: [session()]).isEmpty)
    }

    func testExistingImmediateTurnBlocksQueueUntilTerminalCompletion() {
        let held = row("held", at: 2)
        var direct = row("direct", at: 1, state: .sending, waiting: false)
        direct.chatQueue = nil
        XCTAssertTrue(ChatMessageQueuePolicy.ready([held, direct], observed: [session()]).isEmpty)
        direct.state = .delivered
        XCTAssertEqual(ChatMessageQueuePolicy.ready([held, direct], observed: [session()]), [held.id])
    }
}
