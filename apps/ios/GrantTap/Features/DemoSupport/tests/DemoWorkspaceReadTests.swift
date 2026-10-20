import XCTest
@testable import GrantTap

@MainActor
final class DemoWorkspaceReadTests: XCTestCase {
    func testReadRemainsPendingUntilTheTestCompletesItsReply() async throws {
        let completion = DemoWorkspaceReadCompletion()
        let started = expectation(description: "Read started")
        var finished = false
        let task = Task { started.fulfill(); try await completion.wait(); finished = true }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertFalse(finished)
        completion.finish()
        try await task.value
        XCTAssertTrue(finished)
    }

    func testCompletionBeforeRegistrationIsRetainedForTheNextRead() async throws {
        let completion = DemoWorkspaceReadCompletion()
        completion.finish()
        try await completion.wait()
        try await completion.wait()
    }

    func testCancelledReadsLeaveWithoutWaitingForAReply() async {
        let completion = DemoWorkspaceReadCompletion()
        let started = expectation(description: "Read started")
        let task = Task { started.fulfill(); try await completion.wait() }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { try await task.value; XCTFail("Cancelled read must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        completion.finish()

        let cancelledBeforeStart = Task { try await completion.wait() }
        cancelledBeforeStart.cancel()
        do { try await cancelledBeforeStart.value; XCTFail("Cancelled read must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
