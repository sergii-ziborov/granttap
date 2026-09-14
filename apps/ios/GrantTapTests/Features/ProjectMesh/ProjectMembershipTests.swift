import XCTest
@testable import GrantTap

final class ProjectMembershipTests: XCTestCase {
    private func computer(_ id: String, label: String) -> LinkedComputer {
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.ai", room: id, role: "phone",
            deviceName: label, senderId: "phone", myPublicKey: "a",
            mySecretKey: "b", peerPublicKey: "c", pushAuth: "d"
        )
        return LinkedComputer(
            id: id, pairing: pairing, label: label, addedAt: 1,
            lastCatalogAt: 1, lastMachineName: label
        )
    }

    private func snapshot(boundTo endpoints: [String]) -> ProjectMeshSnapshot {
        let bindings = endpoints.enumerated().map { index, endpoint in
            ProjectBindingSummary(
                bindingId: "binding-\(index)", projectId: "project", endpointId: endpoint,
                repositoryId: "repo", displayName: endpoint, available: true
            )
        }
        return .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            bindings: bindings,
            tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: 1
        )
    }

    func testAPairedComputerOutsideTheProjectIsNamedRatherThanHidden() {
        // A binding is discovered by the computer that holds the repository, so
        // the phone can only report which paired computers are absent.
        let unbound = ProjectMembership.unbound(
            snapshot: snapshot(boundTo: ["mac-studio"]),
            paired: [computer("mac-studio", label: "Studio"), computer("air", label: "Air")]
        )
        XCTAssertEqual(unbound.map(\.endpointId), ["air"])
        XCTAssertEqual(unbound.map(\.displayName), ["Air"])
    }

    func testUnboundComputersReadInAStableOrder() {
        let unbound = ProjectMembership.unbound(
            snapshot: snapshot(boundTo: []),
            paired: [computer("z", label: "Zulu"), computer("a", label: "alpha")]
        )
        XCTAssertEqual(unbound.map(\.displayName), ["alpha", "Zulu"])
    }

    func testNothingIsExplainedWhenEveryComputerAlreadyTakesPart() {
        XCTAssertTrue(ProjectMembership.everyComputerParticipates(
            snapshot: snapshot(boundTo: ["mac-studio"]),
            paired: [computer("mac-studio", label: "Studio")]
        ))
        XCTAssertFalse(ProjectMembership.everyComputerParticipates(
            snapshot: snapshot(boundTo: ["mac-studio"]),
            paired: [computer("mac-studio", label: "Studio"), computer("air", label: "Air")]
        ))
        // No paired computer at all is a pairing problem, not a Project one.
        XCTAssertFalse(ProjectMembership.everyComputerParticipates(
            snapshot: snapshot(boundTo: []), paired: []
        ))
    }

    func testAdmissionCopiesTheKeyFromAComputerThatAlreadyHasIt() {
        // The Project key cannot be conjured; it is copied from a participant.
        XCTAssertEqual(
            ProjectMeshAdmission.sourceRoom(target: "air", participating: ["mac", "studio"]),
            "mac", "a stable choice, not whichever room the set happened to yield"
        )
        XCTAssertNil(ProjectMeshAdmission.sourceRoom(target: "air", participating: ["air"]))
        XCTAssertNil(ProjectMeshAdmission.sourceRoom(target: "air", participating: []))
    }

    func testOnlyAPairedComputerOutsideTheProjectCanBeAdmitted() {
        let paired = [computer("air", label: "Air"), computer("mac", label: "Mac")]
        XCTAssertTrue(ProjectMeshAdmission.canAdmit(
            target: "air", participating: ["mac"], paired: paired
        ))
        // Already inside.
        XCTAssertFalse(ProjectMeshAdmission.canAdmit(
            target: "mac", participating: ["mac"], paired: paired
        ))
        // Not paired: the phone has no device box to hand the key through.
        XCTAssertFalse(ProjectMeshAdmission.canAdmit(
            target: "stranger", participating: ["mac"], paired: paired
        ))
        // No participant holds the key yet, so there is nothing to copy.
        XCTAssertFalse(ProjectMeshAdmission.canAdmit(
            target: "air", participating: [], paired: paired
        ))
    }

    @MainActor
    func testAdmissionIsRefusedWithoutAProjectToCopyFrom() {
        let model = AppModel()
        model.connectionRegistry = .init(
            connections: [computer("air", label: "Air")], preferredId: "air"
        )
        // No snapshot and no participant: nothing to grant.
        XCTAssertFalse(model.admitComputerToProject(projectId: "project", room: "air"))
        XCTAssertNil(model.meshProjectSourceRooms["project"])
    }

    func testOnlyTheComputerJustPairedIsAdmitted() {
        // The pairing sheet reports success without saying which computer, so
        // the new room is whatever was not there when the sheet opened.
        let before: Set<String> = ["mac"]
        let after = [computer("mac", label: "Mac"), computer("air", label: "Air")]
        XCTAssertEqual(ProjectMembership.newlyPaired(before: before, paired: after), ["air"])
        // Nothing new: a sheet dismissed without pairing admits nobody.
        XCTAssertEqual(
            ProjectMembership.newlyPaired(before: ["mac", "air"], paired: after), []
        )
        // Two at once read in a stable order.
        XCTAssertEqual(
            ProjectMembership.newlyPaired(before: [], paired: after), ["air", "mac"]
        )
    }
}
