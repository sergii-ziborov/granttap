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

    func testCursorTaskClonesFoldIntoTheParentChat() {
        let parentId = "077ac587-8ac9-459c-b58a-8278f2767635"
        let cloneId = "task-3ef3af57-1111-4111-8111-1234567890ab"
        var parent = SessionInfo(
            sessionId: parentId, agent: "cursor", projectId: "project",
            taskId: "task-parent", title: "GrantTap MCP configuration issues",
            cwd: "/Users/serhiirihgt/dev/granttap-mcp", state: "working",
            startedAt: 1, lastActivityAt: 5_000, tokensSession: 11, tokensLastTurn: 2
        )
        parent.childThreads = [
            ChildThreadInfo(
                threadId: cloneId, parentThreadId: parentId, title: "Explore",
                depth: 1, state: "working", startedAt: 2, lastActivityAt: 4_000,
                tokensSession: 0, tokensLastTurn: 0
            )
        ]
        let clone = SessionInfo(
            sessionId: cloneId, agent: "cursor", projectId: "project",
            taskId: "task-clone", title: "GrantTap MCP configuration issues",
            cwd: "/Users/serhiirihgt/dev/granttap-mcp", state: "working",
            startedAt: 2, lastActivityAt: 4_000, tokensSession: 0, tokensLastTurn: 0
        )
        let model = AppModel()
        model.sessions = [parent, clone]
        model.meshSnapshots["project"] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "granttap-mcp", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/x/granttap-mcp", createdAt: 1),
            tasks: [
                .init(taskId: "task-parent", projectId: "project", title: "GrantTap MCP configuration issues",
                      goal: "Fix pairing", state: "working", ownerSessionId: parentId,
                      createdAt: 1, updatedAt: 5_000),
                .init(taskId: "task-clone", projectId: "project", title: "GrantTap MCP configuration issues",
                      goal: "Fix pairing", state: "working", ownerSessionId: cloneId,
                      createdAt: 2, updatedAt: 4_000),
            ],
            executions: [
                .init(taskId: "task-parent", sessionId: parentId, provider: "cursor",
                      computerId: "Mac", workspace: "/repo", startedAt: 1),
                .init(taskId: "task-clone", sessionId: cloneId, provider: "cursor",
                      computerId: "Mac", workspace: "/repo", startedAt: 2),
            ],
            claims: [], dependencies: [], events: [], generatedAt: 10
        )

        let items = TaskListCatalog.items(model: model, sessions: [parent, clone])
        XCTAssertEqual(items.filter { $0.currentSession?.sessionId == parentId }.count, 1)
        XCTAssertFalse(items.contains { $0.currentSession?.sessionId == cloneId })
        XCTAssertFalse(items.contains { $0.sessionIds.contains(cloneId) })
        XCTAssertFalse(items.contains { $0.taskId == "task-clone" })

        let filtered = AppModel.filterRealCatalogSessions([parent, clone], allowDemo: false)
        XCTAssertEqual(filtered.map(\.sessionId), [parentId])

        XCTAssertEqual(model.resolvedSessionId(cloneId), parentId)
    }

    func testOrphanCursorTaskCloneIsNotAWorkingCard() {
        let cloneId = "task-aaaaaaaa-1111-4111-8111-1234567890ab"
        let model = AppModel()
        model.meshSnapshots["project"] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "granttap-mcp", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/x/granttap-mcp", createdAt: 1),
            tasks: [
                .init(taskId: "task-clone", projectId: "project", title: "GrantTap MCP configuration issues",
                      goal: "Fix pairing", state: "working", ownerSessionId: cloneId,
                      createdAt: 2, updatedAt: 4_000),
            ],
            executions: [
                .init(taskId: "task-clone", sessionId: cloneId, provider: "cursor",
                      computerId: "Mac", workspace: "/repo", startedAt: 2),
            ],
            claims: [], dependencies: [], events: [], generatedAt: 10
        )

        let items = TaskListCatalog.items(model: model, sessions: [])
        XCTAssertTrue(items.isEmpty, "a clone with no parent chat is not a card")
    }
}
