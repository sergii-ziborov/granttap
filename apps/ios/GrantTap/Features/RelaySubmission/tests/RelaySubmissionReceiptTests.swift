import Foundation
import XCTest
@testable import GrantTap

final class RelaySubmissionReceiptTests: XCTestCase {
    func testOnlyBoundedControlReceiptsForExplicitSubmissionsAreAccepted() throws {
        for prefix in ["user-message-", "approval-decision-", "attachment-"] {
            let data = Data("{\"type\":\"relay.stored\",\"deliveryId\":\"\(prefix)fixture\"}".utf8)
            XCTAssertEqual(try XCTUnwrap(RelaySubmissionReceipt.decode(data)).deliveryId, prefix + "fixture")
            XCTAssertNil(RelaySubmissionReceipt.decode(Data("{\"type\":\"relay.stored\",\"deliveryId\":\"\(prefix)\"}".utf8)))
        }
        for value in ["{}", "{\"type\":\"relay.ack\",\"deliveryId\":\"user-message-fixture\"}",
                      "{\"type\":\"relay.stored\",\"deliveryId\":\"catalog-fixture\"}",
                      String(repeating: "x", count: 4097)] {
            XCTAssertNil(RelaySubmissionReceipt.decode(Data(value.utf8)))
        }
        XCTAssertFalse(RelaySubmissionReceipt.isSubmission("user-message-" + String(repeating: "x", count: 180)))
        let dropped = Data("{\"type\":\"relay.dropped\",\"deliveryId\":\"user-message-fixture\",\"reason\":\"full\"}".utf8)
        XCTAssertEqual(RelaySubmissionReceipt.decode(dropped)?.reason, "full")
    }
}
