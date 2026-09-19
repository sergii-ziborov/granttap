import SwiftUI
import XCTest
@testable import GrantTap

final class ProjectComputerRosterTests: XCTestCase {
    private func snapshot(boundTo endpoints: [String]) -> ProjectMeshSnapshot {
        let bindings = endpoints.enumerated().map { index, endpoint in
            ProjectBindingSummary(
                bindingId: "binding-\(index)", projectId: "project", endpointId: endpoint,
                repositoryId: "repo", displayName: endpoint, available: true
            )
        }
        return .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(
                projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                canonicalRepositoryId: "repo", createdAt: 1
            ),
            bindings: bindings,
            tasks: [
                .init(
                    taskId: "t1", projectId: "project", title: "Ship",
                    goal: "Ship", state: "working", ownerSessionId: "s1",
                    createdAt: 1, updatedAt: 1
                ),
                .init(
                    taskId: "t2", projectId: "project", title: "Wait",
                    goal: "Wait", state: "blocked", ownerSessionId: "s2",
                    createdAt: 1, updatedAt: 1
                ),
            ],
            executions: [], claims: [], dependencies: [], events: [],
            generatedAt: 1
        )
    }

    func testHostsAreBindingsPlusParticipatingRoomsMinusHiddenOnes() {
        let mesh = snapshot(boundTo: ["studio", "air"])
        XCTAssertEqual(
            ProjectComputerRoster.hostIds(
                snapshot: mesh, participating: ["studio", "air", "member-phone"],
                memberRooms: ["member-phone"]
            ),
            ["air", "studio"]
        )
        XCTAssertEqual(
            ProjectComputerRoster.hostIds(
                snapshot: mesh, participating: ["studio", "tower"],
                archived: ["air"], removed: ["tower"]
            ),
            ["studio"]
        )
    }

    func testArchivedIdsKeepAComputerThatNoLongerReports() {
        XCTAssertEqual(
            ProjectComputerRoster.archivedIds(
                snapshot: snapshot(boundTo: ["studio"]), archived: ["air", "studio"]
            ),
            ["studio", "air"]
        )
    }

    func testStatsSummaryNamesComputersThenCallsThenTokens() {
        let mesh = snapshot(boundTo: ["studio"])
        XCTAssertEqual(
            ProjectMeshStatsPresentation.summary(
                snapshot: mesh, events: [], sessions: [], computerCount: 1
            ),
            String(format: L("%d computer"), 1)
        )
        XCTAssertEqual(ProjectMeshStatsPresentation.taskCount(mesh, state: "working"), 1)
        XCTAssertEqual(ProjectMeshStatsPresentation.taskCount(mesh, state: "blocked"), 1)
    }

    func testRemovedPairedComputerShowsAsUnboundAgain() {
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.ai", room: "air", role: "phone",
            deviceName: "Air", senderId: "phone", myPublicKey: "a",
            mySecretKey: "b", peerPublicKey: "c", pushAuth: "d"
        )
        let air = LinkedComputer(
            id: "air", pairing: pairing, label: "Air", addedAt: 1,
            lastCatalogAt: 1, lastMachineName: "Air"
        )
        let unbound = ProjectMembership.unbound(
            snapshot: snapshot(boundTo: ["air"]),
            paired: [air],
            removed: ["air"]
        )
        XCTAssertEqual(unbound.map(\.endpointId), ["air"])
    }
}

@MainActor
final class ProjectComputerMembershipTests: XCTestCase {
    override func tearDown() {
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    func testArchiveRestoreAndRemoveStayOnThisProject() {
        let model = AppModel()
        model.agentMeshPreferences.meshEnabled = true
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        model.meshSnapshots[snapshot.projectId] = snapshot
        model.meshProjectSourceRooms[snapshot.projectId] = ["mac", "workstation"]

        XCTAssertTrue(model.archiveProjectComputer(projectId: snapshot.projectId, endpointId: "mac"))
        XCTAssertEqual(model.computerDisposition("mac", projectId: snapshot.projectId), .archived)
        XCTAssertTrue(model.hiddenComputers(for: snapshot.projectId).contains("mac"))
        XCTAssertTrue(model.restoreProjectComputer(projectId: snapshot.projectId, endpointId: "mac"))
        XCTAssertEqual(model.computerDisposition("mac", projectId: snapshot.projectId), .active)

        XCTAssertTrue(model.removeProjectComputer(projectId: snapshot.projectId, endpointId: "mac"))
        XCTAssertEqual(model.computerDisposition("mac", projectId: snapshot.projectId), .removed)
        XCTAssertFalse(model.computerRooms(for: snapshot.projectId).contains("mac"))
        XCTAssertFalse(model.archiveProjectComputer(projectId: snapshot.projectId, endpointId: "mac"))
    }

    func testARemovedComputerIsNotReadmittedByALaterSnapshot() {
        let model = AppModel()
        model.agentMeshPreferences.meshEnabled = true
        model.removedProjectComputers["project"] = ["source"]
        model.receive(
            ProjectGovernanceViewFixtures.projectSnapshot(), fromRoom: "source"
        )
        XCTAssertFalse(model.meshProjectSourceRooms["project"]?.contains("source") == true)
        XCTAssertEqual(model.meshSnapshots["project"]?.project.name, "GrantTap")
    }

    func testExecutionAndStatsScreensRenderAllHostsAndAComputer() {
        let model = AppModel()
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        model.meshSnapshots[snapshot.projectId] = snapshot
        model.meshProjectSourceRooms[snapshot.projectId] = ["mac", "workstation"]
        RenderProbe.render(ProjectExecutionView(snapshot: snapshot, model: model))
        RenderProbe.render(ProjectMeshStatsView(snapshot: snapshot, model: model))
        RenderProbe.render(ProjectComputerDetailView(
            endpointId: "mac", snapshot: snapshot, model: model
        ))
        RenderProbe.render(ProjectMembersView(snapshot: snapshot, model: model))
        XCTAssertEqual(
            ProjectComputerRoster.hostIds(snapshot: snapshot),
            ["mac", "workstation"]
        )
    }
}
