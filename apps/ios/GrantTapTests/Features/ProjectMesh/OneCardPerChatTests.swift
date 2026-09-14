import XCTest
@testable import GrantTap

@MainActor
final class OneCardPerChatTests: XCTestCase {
    private func snapshot(projectId: String, generatedAt: Double, computer: String) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(projectId: projectId, name: "gopherforge", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/x/gopherforge", createdAt: 1),
            tasks: [.init(taskId: "task-\(projectId)", projectId: projectId, title: "давай опубликуем",
                          goal: "goal", state: "planned", ownerSessionId: "chat", createdAt: 1, updatedAt: 1)],
            executions: [.init(taskId: "task-\(projectId)", sessionId: "chat", provider: "claude",
                               computerId: computer, workspace: "/repo", startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: generatedAt
        )
    }

    private var chat: SessionInfo {
        SessionInfo(
            sessionId: "chat", agent: "claude", projectId: "project-new", taskId: "task-project-new",
            title: "давай опубликуем", cwd: "/repo", summary: "Посмотрел курс замерами",
            state: "idle", startedAt: 1, lastActivityAt: 5_000, tokensSession: 0, tokensLastTurn: 0
        )
    }

    func testOneChatIsOneCardEvenWhenTwoProjectIdentitiesClaimIt() {
        let model = AppModel()
        model.meshSnapshots["project-old"] = snapshot(projectId: "project-old", generatedAt: 10, computer: "Serhiis-MacBook-Pro.local")
        model.meshSnapshots["project-new"] = snapshot(projectId: "project-new", generatedAt: 20, computer: "Mac.lan")
        let items = TaskListCatalog.items(model: model, sessions: [chat])
        XCTAssertEqual(items.filter { $0.currentSession?.sessionId == "chat" }.count, 1,
                       "two Project identities, one conversation, one card")

        // A session the Mesh has not claimed beside its Task: still one card, the Task's.
        var unclaimed = chat
        unclaimed.projectId = nil
        unclaimed.taskId = nil
        model.meshSnapshots = ["project-new": snapshot(projectId: "project-new", generatedAt: 20, computer: "Mac.lan")]
        let mixed = TaskListCatalog.items(model: model, sessions: [unclaimed])
        XCTAssertEqual(mixed.filter { $0.currentSession?.sessionId == "chat" }.count, 1)
        XCTAssertEqual(mixed.first { $0.currentSession?.sessionId == "chat" }?.taskId, "task-project-new")

        // Items without a chat are never folded into each other.
        let orphan = TaskListItem(
            id: "task:x", destination: .task(.init(projectId: "x", taskId: "t")), projectId: "x", taskId: "t",
            projectName: "x", title: "no chat", summary: nil, state: "planned", ownerExecution: nil,
            currentSession: nil, historicalExecutions: [], sessionIds: [], lastActivityAt: 1
        )
        XCTAssertEqual(TaskListCatalog.onePerChat([orphan, orphan]).count, 2)
    }

    func testTheOlderIdentityOfTheSameRepositoryIsDropped() {
        let old = snapshot(projectId: "project-old", generatedAt: 10, computer: "Serhiis-MacBook-Pro.local")
        let new = snapshot(projectId: "project-new", generatedAt: 20, computer: "Mac.lan")
        let other = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project-other", projectId: "project-other",
            project: .init(projectId: "project-other", name: "nodvox", repositoryRoot: "/nodvox",
                           canonicalRepositoryId: "github.com/x/nodvox", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 30
        )
        let snapshots = ["project-old": old, "project-new": new, "project-other": other]
        XCTAssertEqual(ProjectMeshLogic.staleIdentities(in: snapshots, besides: new), ["project-old"])
        XCTAssertEqual(ProjectMeshLogic.staleIdentities(in: snapshots, besides: old), [],
                       "an older snapshot never evicts a newer identity")
        XCTAssertEqual(ProjectMeshLogic.staleIdentities(in: snapshots, besides: other), [])
    }

    func testARetiredBindingUnderAFormerNameIsNotASecondComputer() {
        func binding(_ id: String, endpoint: String, repository: String, available: Bool) -> ProjectBindingSummary {
            .init(bindingId: id, projectId: "p", endpointId: endpoint, repositoryId: repository,
                  displayName: repository, available: available)
        }
        let live = binding("new", endpoint: "Serhiis-MacBook-Pro.local", repository: "gopherforge", available: true)
        let retired = binding("old", endpoint: "Mac.lan", repository: "gopherforge", available: false)
        let offline = binding("other", endpoint: "studio", repository: "nodvox", available: false)
        XCTAssertEqual(ProjectMeshLogic.visibleBindings([retired, live, offline]).map(\.bindingId), ["new", "other"],
                       "the retired twin hides; a repository nobody offers stays listed as unavailable")
        XCTAssertEqual(ProjectMeshLogic.visibleBindings([retired]).map(\.bindingId), ["old"])
    }
}
