import XCTest
@testable import GrantTap

final class RelaySubmissionTrackerTests: XCTestCase {
    func testStoredReceiptCompletesOnlyItsRegisteredSubmissionOnce() {
        let tracker = RelaySubmissionTracker()
        var results: [Error?] = []
        XCTAssertNotNil(tracker.register("one") { results.append($0) })
        XCTAssertFalse(tracker.complete("other"))
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(tracker.complete("one"))
        XCTAssertEqual(results.count, 1)
        if let result = results.first { XCTAssertNil(result) }
        XCTAssertFalse(tracker.complete("one"))
    }

    func testRetriesShareTheSameImmutableStorageReceipt() {
        let tracker = RelaySubmissionTracker()
        var count = 0
        for _ in 0..<2 { _ = tracker.register("same") { XCTAssertNil($0); count += 1 } }
        XCTAssertTrue(tracker.complete("same"))
        XCTAssertEqual(count, 2)
    }

    func testExpiredAttemptCannotExpireTheNextAttemptWithTheSameID() {
        let tracker = RelaySubmissionTracker()
        var failures = 0
        let old = tracker.register("same") { if $0 != nil { failures += 1 } }!
        tracker.expire("same", token: old)
        XCTAssertEqual(failures, 1)
        var accepted = false
        _ = tracker.register("same") { accepted = $0 == nil }
        tracker.expire("same", token: old)
        XCTAssertTrue(tracker.complete("same"))
        XCTAssertTrue(accepted)
    }

    func testCapacityAndDisconnectPreserveEveryCompletion() {
        let tracker = RelaySubmissionTracker(limit: 1)
        var disconnected = false
        _ = tracker.register("first") { disconnected = $0 as? RelaySubmissionFailure == .disconnected }
        var full = false
        XCTAssertNil(tracker.register("second") { full = $0 as? RelaySubmissionFailure == .capacity })
        XCTAssertTrue(full)
        tracker.disconnect()
        XCTAssertTrue(disconnected)
        XCTAssertFalse(tracker.complete("first"))
        XCTAssertNotNil(tracker.register("third") { _ in })
    }

    func testCompletionMayRegisterAnotherSubmissionWithoutDeadlocking() {
        let tracker = RelaySubmissionTracker()
        var next = false
        _ = tracker.register("first") { _ in _ = tracker.register("next") { _ in next = true } }
        tracker.complete("first", error: RelaySubmissionFailure.rejected)
        XCTAssertTrue(tracker.complete("next"))
        XCTAssertTrue(next)
    }
}
