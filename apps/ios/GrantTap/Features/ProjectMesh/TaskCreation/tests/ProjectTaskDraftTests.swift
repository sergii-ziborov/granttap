import XCTest
@testable import GrantTap

@MainActor
final class ProjectTaskDraftTests: XCTestCase {
    func testCreationKeepsExactMeshBindingModelAndEffortAndRetriesSameRequest() throws {
        let context = fixture()
        let draft = ProjectTaskDraft()
        draft.configure(context)
        XCTAssertEqual(draft.endpointId, "mac")
        XCTAssertEqual(draft.bindingId, "mac-work")
        draft.text = "  Synthetic task  "
        draft.model = TurnModel(rawValue: "gpt-6-sol")
        draft.effort = .ultra
        let first = try draft.request(context)
        XCTAssertEqual(first.projectId, "mesh")
        XCTAssertEqual(first.workspace, "/fixture/app")
        XCTAssertEqual(first.text, "Synthetic task")
        XCTAssertEqual(first.model, "gpt-6-sol")
        XCTAssertEqual(first.effort, "ultra")
        XCTAssertEqual(try draft.request(context).operationId, first.operationId)
        draft.confirmedFailure()
        let retry = try draft.request(context)
        XCTAssertNotEqual(retry.operationId, first.operationId)
        draft.text = "A different task"
        XCTAssertNotEqual(try draft.request(context).operationId, retry.operationId)
    }

    func testChangingComputerAndProviderClearsInvalidSelectionsWithoutLosingText() {
        let context = fixture()
        let draft = ProjectTaskDraft()
        draft.configure(context)
        draft.text = "Keep my draft"
        draft.model = TurnModel(rawValue: "gpt-6-sol")
        draft.effort = .ultra
        draft.endpointId = "pc"
        draft.provider = "grok"
        draft.reconcile(context)
        XCTAssertEqual(draft.bindingId, "pc-work")
        XCTAssertNil(draft.model)
        XCTAssertNil(draft.effort)
        XCTAssertEqual(draft.text, "Keep my draft")
        XCTAssertEqual(draft.attachments.count, 0)
    }

    func testPinnedUnconfirmedForeignBindingsAndLongDescriptionsCannotStartTasks() {
        var context = fixture()
        let draft = ProjectTaskDraft()
        draft.configure(context)
        XCTAssertFalse(draft.canCreate(context))
        draft.text = String(repeating: "x", count: 8_001)
        XCTAssertFalse(draft.canCreate(context))
        draft.text = "Synthetic"
        draft.bindingId = "foreign"
        XCTAssertFalse(draft.canCreate(context))
        XCTAssertThrowsError(try draft.request(context))
        context = fixture(policy: .init(mode: "pinned", targetEndpointId: "pc", revision: 1, hostGrantStatus: "pending"))
        draft.configure(context)
        draft.reconcile(context)
        XCTAssertEqual(draft.endpointId, "pc")
        XCTAssertFalse(draft.canCreate(context))
        XCTAssertNotNil(draft.problem(context))
    }

    private func fixture(policy: ProjectExecutionPolicy? = nil) -> ProjectTaskCreationContext {
        let now = Date().timeIntervalSince1970 * 1_000
        let snapshot = ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "mesh", projectId: "mesh",
            project: .init(projectId: "mesh", name: "Synthetic", canonicalRepositoryId: "github.com/fixture/app", createdAt: 1),
            bindings: [
                .init(bindingId: "mac-work", projectId: "mesh", endpointId: "mac", repositoryId: "github.com/fixture/app", displayName: "app", localPathHint: "/fixture/app", available: true),
                .init(bindingId: "pc-work", projectId: "mesh", endpointId: "pc", repositoryId: "github.com/fixture/app", displayName: "app", localPathHint: "C:/fixture/app", available: true),
                .init(bindingId: "foreign", projectId: "another", endpointId: "mac", repositoryId: "other", displayName: "other", localPathHint: "/unrelated", available: true),
            ], modelCatalog: [.init(endpointId: "mac", observedAt: now, models: [
                .init(modelId: "gpt-6-sol", provider: "codex", endpointId: "mac", source: "advertised", supportedEfforts: ["low", "high", "ultra"], observedAt: now),
            ])], tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: now)
        return .init(snapshot: snapshot, policy: policy, enabledProviders: ["codex", "claude", "cursor", "grok"],
            localEndpointId: "mac", rooms: ["pc": "room-pc"])
    }
}
