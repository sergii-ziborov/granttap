import XCTest
@testable import GrantTap

final class TaskTransferAvailabilityTests: XCTestCase {
    func testAllFourProvidersOfferTheSameTransferOnPhoneAndLocalMac() {
        for provider in AgentIdentity.composeIds {
            let session = session(provider)
            XCTAssertTrue(TaskTransferAvailability.canOffer(for: session, linkedComputer: true, localComputer: false))
            XCTAssertTrue(TaskTransferAvailability.canOffer(for: session, linkedComputer: false, localComputer: true))
            XCTAssertFalse(TaskTransferAvailability.canOffer(for: session, linkedComputer: false, localComputer: false))
        }
    }

    func testIncompleteOrUnsupportedChatsDoNotOfferAnUnusableTransfer() {
        var chat = session("unknown")
        XCTAssertFalse(TaskTransferAvailability.canOffer(for: chat, linkedComputer: true, localComputer: true))
        chat = session("codex")
        chat.taskId = nil
        XCTAssertFalse(TaskTransferAvailability.canOffer(for: chat, linkedComputer: true, localComputer: true))
        chat.taskId = "task"
        chat.projectId = "  "
        XCTAssertFalse(TaskTransferAvailability.canOffer(for: chat, linkedComputer: true, localComputer: true))
    }

    private func session(_ provider: String) -> SessionInfo {
        SessionInfo(sessionId: "chat", agent: provider, projectId: "project", taskId: "task",
            state: "idle", startedAt: 1, lastActivityAt: 1, tokensSession: 0, tokensLastTurn: 0)
    }
}
