import XCTest
@testable import GrantTap

@MainActor
final class ProjectEnvironmentDeliveryTests: XCTestCase {
    func testPublicProjectVariablesReachOnlineAndOfflineBoundComputers() throws {
        let model = AppModel()
        defer {
            ProjectGovernancePersistence.clear()
            ProjectPolicyOutboxStore.clear()
        }
        model.agentMeshPreferences.meshEnabled = true
        model.projectPolicyOutbox = []
        model.meshProjectSourceRooms["project"] = ["room-online", "room-offline"]
        model.relaysByRoom["room-online"] = RelayClient(
            pairing: ProjectGovernanceSyncFixtures.pairing(room: "room-online")
        )
        model.receive(
            ProjectGovernanceSyncFixtures.policyStatus(
                endpoint: "mac", provider: "claude", status: .enforced
            ), fromRoom: "room-online"
        )

        let value = ProjectEnvironmentVariable(
            key: "APP_MODE", value: "test", secret: false
        )
        XCTAssertTrue(model.applyProjectEnvironment(
            projectId: "project", shareNonSecrets: false, variables: [value]
        ))

        let online = try XCTUnwrap(model.relaysByRoom["room-online"])
        let packet = try XCTUnwrap(online.pendingSessionPayloads.values.first)
        let sent = try JSONDecoder().decode(ProjectPolicySet.self, from: packet.plain)
        XCTAssertEqual(sent.policy.environment?.variables, [value])
        XCTAssertEqual(sent.policy.environment?.shareNonSecretsWithRepo, false)

        let queued = try XCTUnwrap(model.projectPolicyOutbox.first {
            $0.room == "room-offline"
        })
        XCTAssertEqual(queued.request.policy.environment?.variables, [value])
        XCTAssertEqual(queued.revision, sent.policy.revision)
        online.disconnect()
    }
}
