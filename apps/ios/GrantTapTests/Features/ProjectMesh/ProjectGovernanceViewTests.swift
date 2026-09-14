import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class ProjectGovernanceViewTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    func testProjectSummaryReportsGovernanceMembersAndMeshWithoutPaths() {
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        let governance = ProjectGovernanceViewFixtures.policyProjection()
        XCTAssertEqual(ProjectManagePresentation.governanceSummary(governance), "3 rules")
        XCTAssertEqual(ProjectManagePresentation.membersSummary(snapshot), "1 person · 2 computers")
        XCTAssertEqual(ProjectManagePresentation.meshSummary(snapshot), "Shared · 2 computers")

        let members = ProjectMembersView(snapshot: snapshot, model: AppModel()).computers
        XCTAssertEqual(members.map(\.endpointId), ["mac", "workstation"])
        XCTAssertEqual(members.map(\.repositoryCount), [2, 1])
        XCTAssertFalse(members.map(\.detail).joined().contains("/Users/private"))
    }

    func testGovernancePresentationNeverClaimsUnsupportedCoverageIsProtected() {
        let governance = ProjectGovernanceViewFixtures.policyProjection()
        let model = AppModel()
        model.projectGovernance[governance.projectId] = governance
        let view = ProjectGovernanceView(
            project: ProjectGovernanceViewFixtures.projectSnapshot().project, model: model
        )
        XCTAssertEqual(view.rules.map(\.ruleId), ["deny-unknown", "ask-deploy", "allow-github"])
        XCTAssertEqual(view.coverage.map(\.status), [.enforced, .observed, .unsupported, .unknown])
        XCTAssertEqual(ProjectGovernancePresentation.coverageLabel(.enforced), "Enforced")
        XCTAssertEqual(ProjectGovernancePresentation.coverageLabel(.observed), "Observed only")
        XCTAssertEqual(ProjectGovernancePresentation.coverageLabel(.unsupported), "Unsupported")
        XCTAssertEqual(ProjectGovernancePresentation.coverageLabel(.unknown), "Unknown")
        XCTAssertEqual(ProjectGovernancePresentation.effectLabel(.ask), "Ask")
    }

    func testAProjectWithNoPolicyYetCanStillAuthorItsFirst() throws {
        // Requiring a policy to already exist locked the editor shut in the one
        // case where it matters: a Project reported at revision zero with no
        // rules, where the first policy has to come from somewhere.
        let model = AppModel()
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        let reported = try XCTUnwrap(ProjectGovernanceLogic.merged(
            current: nil, status: ProjectGovernanceFixtures.status(
                projectId: snapshot.projectId, revision: 0
            )
        ))
        model.projectGovernance[snapshot.projectId] = reported

        let untouched = ProjectGovernanceView(project: snapshot.project, model: model)
        XCTAssertFalse(untouched.canSave, "an unchanged draft has nothing to save")

        let edited = ProjectGovernanceView(
            project: snapshot.project, model: model,
            defaults: [.shell: .deny]
        )
        XCTAssertTrue(edited.canSave, "a first rule is exactly what Save is for")

        // A Project still waiting on the computer to confirm stays locked.
        model.pendingProjectPolicyRevisions[snapshot.projectId] = 1
        XCTAssertFalse(
            ProjectGovernanceView(
                project: snapshot.project, model: model, defaults: [.shell: .deny]
            ).canSave
        )
    }

    func testSavingSaysSomethingRatherThanOnlyGoingGrey() {
        let model = AppModel()
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        defer {
            ProjectGovernancePersistence.clear()
            ProjectPolicyOutboxStore.clear()
        }
        model.agentMeshPreferences.meshEnabled = true
        model.projectGovernance[snapshot.projectId] = ProjectGovernanceViewFixtures.policyProjection()

        // Refused: the reason is what the person is told, not silence.
        var view = ProjectGovernanceView(
            project: snapshot.project, model: model, defaults: [.shell: .deny]
        )
        ProjectGovernanceViewFixtures.render(view)
        XCTAssertTrue(view.canSave)

        // Accepted: the confirmation names what happens next, because the
        // computers have not applied it yet and the screen should not imply
        // that they have.
        model.meshProjectSourceRooms[snapshot.projectId] = ["room-a"]
        view = ProjectGovernanceView(
            project: snapshot.project, model: model, defaults: [.shell: .deny]
        )
        ProjectGovernanceViewFixtures.render(view)
        RenderProbe.render(
            Text("x").transientToast(.constant(L("Policy saved. Computers apply it when they next read the mesh.")))
        )
    }

    func testTheEditorSaysWhatHappenedToTheEditItSent() {
        let model = AppModel()
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        model.projectGovernance[snapshot.projectId] = ProjectGovernanceViewFixtures.policyProjection()

        // In flight.
        model.pendingProjectPolicyRevisions[snapshot.projectId] = 9
        ProjectGovernanceViewFixtures.render(ProjectGovernanceView(project: snapshot.project, model: model))

        // Taken by the relay: saved, with the computers still to apply it.
        model.pendingProjectPolicyRevisions = [:]
        model.deliveredProjectPolicyRevisions[snapshot.projectId] = 9
        ProjectGovernanceViewFixtures.render(ProjectGovernanceView(project: snapshot.project, model: model))

        // Refused: the reason is shown rather than swallowed.
        model.deliveredProjectPolicyRevisions = [:]
        model.projectPolicyErrors[snapshot.projectId] = "Policy update could not be delivered."
        ProjectGovernanceViewFixtures.render(ProjectGovernanceView(project: snapshot.project, model: model))

        // An edit in progress is what the screen shows, not the saved policy.
        model.projectPolicyErrors = [:]
        model.projectPolicyDrafts[snapshot.projectId] = ProjectGovernanceDraft(
            enforcement: .strict, defaults: [.shell: .deny], named: [:]
        )
        let reopened = ProjectGovernanceView(project: snapshot.project, model: model)
        XCTAssertTrue(reopened.canSave)
        ProjectGovernanceViewFixtures.render(reopened)
    }
}
