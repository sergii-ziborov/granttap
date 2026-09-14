import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testProjectPolicyInboundRequiresExactSealedScopeAndDispatchesCallbacks() async throws {
        let client = RelayClient(pairing: testPairing(room: "policy-inbound"))
        let status = ProjectGovernanceFixtures.status()
        let acknowledgement = ProjectGovernanceFixtures.acknowledgement()
        let statusData = try JSONEncoder().encode(status)
        let acknowledgementData = try JSONEncoder().encode(acknowledgement)
        let callbacks = expectation(description: "project policy callbacks")
        callbacks.expectedFulfillmentCount = 2
        client.onProjectPolicyStatus = { value in
            XCTAssertEqual(value, status)
            callbacks.fulfill()
        }
        client.onProjectPolicyAck = { value in
            XCTAssertEqual(value, acknowledgement)
            callbacks.fulfill()
        }

        XCTAssertFalse(client.handlePlain(statusData))
        XCTAssertFalse(client.handlePlain(statusData, scopedSessionId: "other"))
        XCTAssertTrue(client.handlePlain(statusData, scopedSessionId: "project"))
        XCTAssertTrue(client.handlePlain(acknowledgementData, scopedSessionId: "project"))
        await fulfillment(of: [callbacks], timeout: 2)
    }

    func testProjectPolicyInboundRejectsMissingCallbackMalformedAndWrongType() throws {
        let client = RelayClient(pairing: testPairing(room: "policy-reject"))
        let statusData = try JSONEncoder().encode(ProjectGovernanceFixtures.status())
        let acknowledgementData = try JSONEncoder().encode(
            ProjectGovernanceFixtures.acknowledgement()
        )
        XCTAssertFalse(client.handlePlain(statusData, scopedSessionId: "project"))
        XCTAssertFalse(client.handlePlain(acknowledgementData, scopedSessionId: "project"))
        client.onProjectPolicyStatus = { _ in }
        client.onProjectPolicyAck = { _ in }
        XCTAssertFalse(client.handlePlain(Data("{}".utf8), scopedSessionId: "project"))
        XCTAssertFalse(client.handlePlain(statusData, scopedSessionId: "wrong"))
        XCTAssertFalse(client.handlePlain(acknowledgementData, scopedSessionId: "wrong"))
    }
}
