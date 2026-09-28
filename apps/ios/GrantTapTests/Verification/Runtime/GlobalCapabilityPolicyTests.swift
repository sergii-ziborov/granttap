import XCTest
@testable import GrantTap

final class GlobalCapabilityPolicyTests: XCTestCase {
    func testGlobalCapabilityPayloadOmitsTaskSession() throws {
        let payload = SessionMcpSet(
            type: "session.mcp.set",
            scope: "global",
            sessionId: nil,
            serverName: "filesystem",
            allowed: false,
            createdAt: 1
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        XCTAssertEqual(object["scope"] as? String, "global")
        XCTAssertNil(object["sessionId"])
        XCTAssertEqual(object["serverName"] as? String, "filesystem")
        XCTAssertEqual(object["allowed"] as? Bool, false)
    }

    @MainActor
    func testMachineStatusConfirmsGlobalCapabilityPolicy() throws {
        let json = Data(#"""
        {
          "type":"sessions.status","machine":"Mac","sessions":[],
          "tokensRecent":0,"tokenWindowHours":12,
          "globalMcpDisabled":["filesystem"],
          "globalSkillsDisabled":["release-check"],
          "globalShellDisabled":true,"generatedAt":1
        }
        """#.utf8)
        let status = try JSONDecoder().decode(SessionsStatus.self, from: json)
        let model = AppModel()
        model.applySessionsStatus(status)
        XCTAssertEqual(model.globalMcpDisabled, ["filesystem"])
        XCTAssertEqual(model.globalSkillsDisabled, ["release-check"])
        XCTAssertTrue(model.globalShellDisabled)
    }

    @MainActor
    func testOfflineGlobalChangesFailClosedWithoutChangingVisiblePolicy() {
        let model = AppModel()
        model.connected = false
        model.globalMcpDisabled = []
        model.globalSkillsDisabled = []
        model.globalShellDisabled = false

        model.setGlobalMcpAllowed("filesystem", allowed: false)
        model.setGlobalSkillAllowed("release-check", allowed: false)
        model.setGlobalShellAllowed(false)

        XCTAssertEqual(model.globalMcpDisabled, [])
        XCTAssertEqual(model.globalSkillsDisabled, [])
        XCTAssertFalse(model.globalShellDisabled)
    }
}
