import XCTest
@testable import GrantTap

final class ConnectionFreshnessTests: XCTestCase {
    func testOnlyBriefTransportLossKeepsFreshComputerVisibleAsLive() {
        let now: Double = 1_000_000
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now - 500,
            heartbeatAt: now - 10_000, catalogAt: 0, socketUpSince: 0, now: now), .live)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now - 2_000,
            heartbeatAt: now - 10_000, catalogAt: 0, socketUpSince: 0, now: now), .phoneOffline)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: now - 500,
            heartbeatAt: now - 100_000, catalogAt: 0, socketUpSince: 0, now: now), .phoneOffline)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: now - 10_000, catalogAt: 0, socketUpSince: now, now: now), .live)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: 0, catalogAt: now - 10_000, socketUpSince: now, now: now), .live)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: 0, catalogAt: now + 40_000, socketUpSince: now, now: now), .macOffline)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: true, disconnectedAt: 0,
            heartbeatAt: 0, catalogAt: 0, socketUpSince: now - 200_000, now: now), .needRepair)
        XCTAssertEqual(ConnectionFreshness.phase(socketUp: false, disconnectedAt: 0,
            heartbeatAt: now, catalogAt: 0, socketUpSince: 0, now: now), .phoneOffline)
    }
}
