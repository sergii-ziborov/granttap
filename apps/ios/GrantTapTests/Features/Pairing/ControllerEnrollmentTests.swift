import XCTest
@testable import GrantTap

@MainActor
final class ControllerEnrollmentTests: XCTestCase {
    func testExplicitActionGetsCodeThenOnlyConfirmedStatusCompletes() async throws {
        let enrollment = ControllerEnrollment()
        var actions: [String] = []
        let pending = try code("pending", link: link(), expiry: now + 60_000)
        await enrollment.create { action in actions.append(action); return pending }
        XCTAssertEqual(actions, ["create"])
        XCTAssertEqual(enrollment.code?.status, .pending)
        XCTAssertNotNil(enrollment.code?.uri)
        await enrollment.refresh { action in actions.append(action); return try self.code("connected") }
        XCTAssertEqual(actions, ["create", "status"])
        XCTAssertEqual(enrollment.code?.status, .connected)
        XCTAssertNil(enrollment.code?.uri)
        XCTAssertFalse(enrollment.failed)
        XCTAssertFalse(enrollment.busy)
        enrollment.clear()
        XCTAssertNil(enrollment.code)
    }

    func testInvalidOrExpiredCodesAreNeverDisplayedAndRetryWorks() async throws {
        let enrollment = ControllerEnrollment()
        for payload in [try code("pending", link: "invalid", expiry: now + 60_000),
                        try code("pending", link: link(), expiry: now - 1),
                        try code("pending", link: link(), expiry: now + 20 * 60_000),
                        try code("connected", link: link()), try code("unknown")] {
            await enrollment.create { _ in payload }
            XCTAssertTrue(enrollment.failed)
            XCTAssertNil(enrollment.code)
        }
        await enrollment.create { _ in throw PairingError.unreachable }
        XCTAssertTrue(enrollment.failed)
        await enrollment.refresh { _ in try self.code("expired") }
        XCTAssertEqual(enrollment.code?.status, .expired)
        XCTAssertFalse(enrollment.failed)
        await enrollment.create { _ in try self.code("unavailable") }
        XCTAssertTrue(enrollment.failed)
        await enrollment.create { _ in try self.code("pending", link: self.link(), expiry: self.now + 60_000) }
        XCTAssertFalse(enrollment.failed)
    }

    func testLeavingPageDiscardsAnInFlightCode() async throws {
        let enrollment = ControllerEnrollment()
        await enrollment.create { _ in
            enrollment.clear()
            return try self.code("pending", link: self.link(), expiry: self.now + 60_000)
        }
        XCTAssertNil(enrollment.code)
        XCTAssertFalse(enrollment.busy)
    }

    func testConcurrentRequestsAndWrongOperationAreRejected() async throws {
        let enrollment = ControllerEnrollment()
        var calls = 0
        await enrollment.create { _ in
            calls += 1
            await enrollment.create { _ in calls += 1; return Data() }
            return try self.code("idle")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(enrollment.code?.status, .idle)
        let wrong = Data("{\"operation\":\"other\",\"status\":\"idle\",\"computer\":\"Mac\"}".utf8)
        await enrollment.create { _ in wrong }
        XCTAssertNil(enrollment.code)
        XCTAssertTrue(enrollment.failed)
        let blank = Data("{\"operation\":\"desktop.controller_enrollment\",\"status\":\"idle\",\"computer\":\"\"}".utf8)
        await enrollment.create { _ in blank }
        XCTAssertTrue(enrollment.failed)
    }

    private var now: Double { Date().timeIntervalSince1970 * 1_000 }
    private func link() -> String {
        "granttap://pair-v2?v=2&u=wss://relay.granttap.com&m=\(String(repeating: "a", count: 32))&k=\(String(repeating: "A", count: 43))"
    }
    private func code(_ status: String, link: String? = nil, expiry: Double? = nil) throws -> Data {
        var value: [String: Any] = ["operation": "desktop.controller_enrollment",
                                    "status": status, "computer": "Test Mac"]
        value["uri"] = link
        value["expires_at"] = expiry
        return try JSONSerialization.data(withJSONObject: value)
    }
}
