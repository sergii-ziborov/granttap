import XCTest
@testable import GrantTap

@MainActor
final class ProjectApprovalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProjectAutoAcceptStore.save([:])
    }

    override func tearDown() {
        ProjectAutoAcceptStore.save([:])
        super.tearDown()
    }

    func testProjectAutoAcceptWireKeepsExplicitClearAndReadsMachineStatus() throws {
        let clear = try XCTUnwrap(RelayClient.projectAutoAcceptPayload(
            projectId: "project-one", level: nil
        ))
        let clearJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: clear) as? [String: Any])
        let clearValue = try XCTUnwrap(clearJSON["autoAcceptProject"] as? [String: Any])
        XCTAssertEqual(clearValue["projectId"] as? String, "project-one")
        XCTAssertTrue(clearValue["level"] is NSNull)

        let set = try XCTUnwrap(RelayClient.projectAutoAcceptPayload(
            projectId: "project-one", level: "safe", baseRevision: 7,
            instanceEpoch: "epoch-12345678", now: 1_000, operationId: "operation-1"
        ))
        let setJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: set) as? [String: Any])
        let setValue = try XCTUnwrap(setJSON["autoAcceptProject"] as? [String: Any])
        XCTAssertEqual(setValue["level"] as? String, "safe")
        XCTAssertEqual(setJSON["baseRevision"] as? Int, 7)
        XCTAssertEqual(setJSON["instanceEpoch"] as? String, "epoch-12345678")
        XCTAssertEqual(setJSON["operationId"] as? String, "operation-1")
        XCTAssertEqual(setJSON["expiresAt"] as? Double, 901_000)

        let status = try JSONDecoder().decode(SessionsStatus.self, from: Data("""
        {"type":"sessions.status","machine":"Mac","sessions":[],"generatedAt":1,
         "autoAcceptByProject":{"project-one":"safe"},"configRevision":7,
         "instanceEpoch":"epoch-12345678"}
        """.utf8))
        XCTAssertEqual(status.autoAcceptByProject?["project-one"], "safe")
        XCTAssertEqual(status.configRevision, 7)
        XCTAssertEqual(status.instanceEpoch, "epoch-12345678")
    }

    func testProjectApprovalRefusesAnUnknownComputer() {
        let model = AppModel()
        XCTAssertFalse(model.setProjectAutoAccept(
            projectId: "project-one", level: "full"
        ))
        XCTAssertNil(model.projectAutoAcceptLevel(
            projectId: "project-one", roomId: "unknown"
        ))
        RenderProbe.render(ProjectApprovalSection(projectId: "project-one", model: model))
    }

    func testConflictingEndpointLevelsMigrateToProjectAskAndProjectsStayIndependent() {
        let model = AppModel()
        model.autoAcceptByProjectByRoom = [
            "room-a": ["project-one": "full", "project-two": "safe"],
            "room-b": ["project-one": "ask", "project-two": "safe"],
        ]
        model.meshProjectSourceRooms = [
            "project-one": ["room-a", "room-b"],
            "project-two": ["room-a", "room-b"],
        ]
        model.migrateProjectAutoAcceptIfNeeded(projectId: "project-one")
        model.migrateProjectAutoAcceptIfNeeded(projectId: "project-two")
        XCTAssertEqual(model.desiredProjectAutoAcceptLevel(projectId: "project-one"), "ask")
        XCTAssertEqual(model.desiredProjectAutoAcceptLevel(projectId: "project-two"), "safe")
        XCTAssertTrue(model.setProjectAutoAccept(projectId: "project-one", level: "full"))
        XCTAssertEqual(model.desiredProjectAutoAcceptLevel(projectId: "project-one"), "full")
        XCTAssertEqual(model.desiredProjectAutoAcceptLevel(projectId: "project-two"), "safe")
        XCTAssertEqual(model.projectAutoAcceptLevel(projectId: "project-one", roomId: "room-b"), "ask",
                       "Desired is not misreported as applied on an endpoint")
        XCTAssertFalse(model.setProjectAutoAccept(projectId: "project-two", level: "invalid"))
    }
}
