import XCTest
@testable import GrantTap

@MainActor
final class TaskHandoffConfirmationPollerTests: XCTestCase {
    func testOpensOnlyAfterReceiptAndDestinationCatalogArrive() async {
        var step = 0
        var reads = 0
        let result = await TaskHandoffConfirmationPoller.wait(lookup: {
            reads += 1
            return step == 0 ? .waiting : .prepared("grok-chat")
        }, destinationAvailable: { $0 == "grok-chat" && step >= 2 }, observing: { true },
           pause: { step += 1 })
        XCTAssertEqual(result, .prepared("grok-chat"))
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(step, 2)
    }

    func testRejectionReturnsItsReasonWithoutWaiting() async {
        var waited = false
        let result = await TaskHandoffConfirmationPoller.wait(lookup: { .failed("Cannot create worktree") },
            destinationAvailable: { _ in false }, observing: { true }, pause: { waited = true })
        XCTAssertEqual(result, .failed("Cannot create worktree"))
        XCTAssertFalse(waited)
    }

    func testTimeoutRemainsUnconfirmedAndCheckingAgainReadsExistingStatus() async {
        var reads = 0
        let first = await TaskHandoffConfirmationPoller.wait(lookup: { reads += 1; return .waiting },
            destinationAvailable: { _ in false }, observing: { true }, attempts: 3, pause: {})
        XCTAssertEqual(first, .waiting)
        XCTAssertEqual(reads, 3)
        let second = await TaskHandoffConfirmationPoller.wait(lookup: { reads += 1; return .prepared("chat") },
            destinationAvailable: { $0 == "chat" }, observing: { true }, pause: {})
        XCTAssertEqual(second, .prepared("chat"))
        XCTAssertEqual(reads, 4)
    }

    func testClosedSheetCannotOpenAChatOnLaterConfirmation() async {
        var reads = 0
        let result = await TaskHandoffConfirmationPoller.wait(lookup: { reads += 1; return .prepared("chat") },
            destinationAvailable: { _ in true }, observing: { false }, pause: {})
        XCTAssertNil(result)
        XCTAssertEqual(reads, 0)
    }

    func testCancellationStopsObservation() async {
        let result = await TaskHandoffConfirmationPoller.wait(lookup: { .waiting },
            destinationAvailable: { _ in true }, observing: { true }, pause: { throw CancellationError() })
        XCTAssertNil(result)
    }

    func testReceiptWithoutVisibleDestinationCannotReportAnOpenedChat() async {
        let result = await TaskHandoffConfirmationPoller.wait(lookup: { .prepared("not-in-catalog") },
            destinationAvailable: { _ in false }, observing: { true }, attempts: 1, pause: {})
        XCTAssertEqual(result, .waiting)
    }
}
