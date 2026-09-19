import XCTest
@testable import GrantTap

final class AutoAcceptPresentationTests: XCTestCase {
    func testResolutionPrefersPauseThenChatThenProjectThenMachine() {
        XCTAssertEqual(
            AutoAcceptPresentation.resolved(
                paused: true, session: "full", project: "safe", machine: "except_push"
            ),
            .ask
        )
        XCTAssertEqual(
            AutoAcceptPresentation.resolved(
                paused: false, session: "safe", project: "full", machine: "ask"
            ),
            .safe
        )
        XCTAssertEqual(
            AutoAcceptPresentation.resolved(
                paused: false, session: nil, project: "except_push", machine: "ask"
            ),
            .exceptPush
        )
        XCTAssertEqual(
            AutoAcceptPresentation.resolved(
                paused: false, session: nil, project: nil, machine: "full"
            ),
            .full
        )
    }

    func testMatrixMatchesTheMacHook() {
        XCTAssertTrue(AutoAcceptPresentation.allows(.safe, .read))
        XCTAssertFalse(AutoAcceptPresentation.allows(.safe, .edit))
        XCTAssertTrue(AutoAcceptPresentation.allows(.exceptPush, .edit))
        XCTAssertTrue(AutoAcceptPresentation.allows(.exceptPush, .bash))
        XCTAssertFalse(AutoAcceptPresentation.allows(.exceptPush, .gitPush))
        XCTAssertTrue(AutoAcceptPresentation.allows(.exceptDestructive, .gitPush))
        XCTAssertFalse(AutoAcceptPresentation.allows(.exceptDestructive, .gitForce))
        XCTAssertTrue(AutoAcceptPresentation.allows(.full, .destructive))
        XCTAssertFalse(AutoAcceptPresentation.allows(.ask, .read))
    }

    func testRowSummaryNamesTheProjectOrTheInheritedComputer() {
        XCTAssertEqual(
            AutoAcceptPresentation.summary(paused: true, project: "full", machine: "ask"),
            L("Paused")
        )
        XCTAssertEqual(
            AutoAcceptPresentation.summary(paused: false, project: "safe", machine: "ask"),
            AutoAcceptLevel.safe.title
        )
        XCTAssertTrue(
            AutoAcceptPresentation.summary(paused: false, project: nil, machine: "except_push")
                .contains(L("Inherited"))
        )
    }
}

@MainActor
final class AutoAcceptModuleCoverageTests: XCTestCase {
    func testProjectAndSettingsScreensRender() {
        let model = AppModel()
        model.autoAcceptDefault = "ask"
        model.autoAcceptByProject["project"] = "except_push"
        let snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(
                projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                canonicalRepositoryId: "github.com/example/granttap", createdAt: 1
            ),
            tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: 1
        )
        var session = SessionInfo(
            sessionId: "chat", agent: "cursor", title: "Ship",
            state: "working", startedAt: 1, lastActivityAt: 1,
            tokensSession: 0, tokensLastTurn: 0
        )
        session.projectId = "project"
        model.sessions = [session]
        RenderProbe.render(ProjectAutoAcceptView(snapshot: snapshot, model: model))
        RenderProbe.render(AutoAcceptSettingsView(model: model))
        model.setProjectAutoAccept("project", "safe")
        XCTAssertEqual(model.autoAcceptByProject["project"], "safe")
        XCTAssertEqual(model.autoAcceptLevel(for: session), "safe")
        model.autoAcceptBySession["chat"] = "full"
        XCTAssertEqual(model.autoAcceptLevel(for: session), "full")
        model.autoAcceptBySession.removeValue(forKey: "chat")
        model.setProjectAutoAccept("project", nil)
        XCTAssertEqual(model.autoAcceptLevel(for: session), "ask")
    }
}
