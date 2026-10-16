import XCTest
@testable import GrantTap

@MainActor
final class PreparedTransferRoutingTests: XCTestCase {
    func testAnAlreadyPreparedComputerTransferIsAnObservationAndNeverPhoneForwardedAgain() throws {
        let payload = """
        {"type":"mesh.event","sessionId":"task","eventId":"prepared-transfer","projectId":"project",
        "taskId":"task","sourceSessionId":"source","eventType":"HANDOFF_REQUEST","createdAt":100,
        "payload":{"capsule":{"title":"Task","launch":"on_message","contextHash":"\(String(repeating: "a", count: 64))",
        "taskId":"task","goal":"Synthetic goal","currentStatus":"Ready","sourceProvider":"codex",
        "sourceComputer":"computer-a","targetProvider":"grok","targetComputer":"computer-b",
        "repository":"repo","baseSha":"\(String(repeating: "b", count: 40))","workingTree":"clean",
        "filesChanged":[],"dependencies":[],"resourceClaims":[],"remainingWork":[],"importantDecisions":[],"createdAt":100}}}
        """
        let event = try JSONDecoder().decode(ProjectMeshEvent.self, from: Data(payload.utf8))
        XCTAssertNil(ProjectMeshLogic.destinationRoom(for: event,
            sessionRooms: [:], computerRooms: ["computer-b": "destination-room"]))
        XCTAssertFalse(ProjectMeshLogic.requiresHandoffAuthorization(event, locallyAuthorized: false))
        var legacy = event
        legacy.payload.capsule?.launch = nil
        XCTAssertEqual(ProjectMeshLogic.destinationRoom(for: legacy,
            sessionRooms: [:], computerRooms: ["computer-b": "destination-room"]), "destination-room")
        XCTAssertTrue(ProjectMeshLogic.requiresHandoffAuthorization(legacy, locallyAuthorized: false))
    }
}
