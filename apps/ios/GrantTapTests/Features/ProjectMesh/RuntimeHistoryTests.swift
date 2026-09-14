import XCTest
@testable import GrantTap

final class RuntimeHistoryTests: XCTestCase {
    private func event(
        phase: String, source: String = "transcript", revision: String? = nil,
        contentHash: String? = nil
    ) -> ProjectInvocationEvent {
        ProjectInvocationEvent(
            event_id: "event-1", invocation_id: "call-1", project_id: "project-1",
            task_id: "task-1", execution_id: "execution-1", provider: "claude",
            native_call_id: "native-1", session_id: "session-1", tool_name: "Edit",
            phase: phase, source: source, occurred_at: 1_000,
            repository_id: "repo-1", worktree: "/work/repo-1",
            resource: "src/index.ts", revision: revision, content_hash: contentHash,
            capability_artifact_hash: nil, policy_revision: nil, policy_rule_id: nil
        )
    }

    func testReportedSuccessRemainsDistinctFromVerifiedFilesystemChange() {
        let reported = event(phase: "reported_success")
        XCTAssertTrue(reported.isWellFormed)
        let unverified = event(phase: "change_observed", source: "transcript")
        XCTAssertFalse(unverified.isWellFormed)
        let verified = ProjectInvocationEvent(
            event_id: "event-2", invocation_id: "call-1", project_id: "project-1",
            task_id: "task-1", execution_id: "execution-1", provider: "claude",
            native_call_id: "native-1", session_id: "session-1", tool_name: "Edit",
            phase: "change_observed", source: "filesystem", occurred_at: 1_001,
            repository_id: "repo-1", worktree: "/work/repo-1",
            resource: "src/index.ts", revision: "revision-1",
            content_hash: String(repeating: "a", count: 64),
            capability_artifact_hash: nil, policy_revision: nil, policy_rule_id: nil
        )
        XCTAssertTrue(verified.isWellFormed)
    }

    func testMalformedFilesystemHashCannotClaimAConfirmedChange() {
        let malformed = event(
            phase: "change_observed", source: "filesystem",
            revision: "revision-1", contentHash: "not-a-sha256"
        )
        XCTAssertFalse(malformed.isWellFormed)
    }

    func testProjectPageRejectsCrossTaskAndOutOfOrderEvidence() {
        let valid = ProjectInvocationPage(
            type: "mesh.invocation.page", sessionId: "project-1", projectId: "project-1",
            taskId: "task-1", requestId: "request-1", sourceEndpointId: "computer-1",
            availability: "ready", events: [.init(sequence: 2, event: event(phase: "requested"))],
            nextSequence: 2, previousSequence: 2, hasMore: false, hasOlder: false,
            generatedAt: 2_000
        )
        XCTAssertTrue(valid.isWellFormed)
        let wrongTask = ProjectInvocationPage(
            type: valid.type, sessionId: valid.sessionId, projectId: valid.projectId,
            taskId: "task-2", requestId: valid.requestId,
            sourceEndpointId: valid.sourceEndpointId, availability: valid.availability,
            events: valid.events, nextSequence: valid.nextSequence,
            previousSequence: valid.previousSequence, hasMore: false, hasOlder: false,
            generatedAt: valid.generatedAt
        )
        XCTAssertFalse(wrongTask.isWellFormed)
    }

    @MainActor
    func testInvocationHistoryAcceptsOnlyTheRequestedRoomAndTask() {
        let model = AppModel()
        let projectId = "project-1"
        let taskId = "task-1"
        model.meshSnapshots[projectId] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(
                projectId: projectId, name: "Runtime test", repositoryRoot: "/repo",
                canonicalRepositoryId: "repo-1", createdAt: 1_000
            ),
            tasks: [.init(
                taskId: taskId, projectId: projectId, title: "Edit", goal: "Edit",
                state: "working", ownerSessionId: nil, createdAt: 1_000, updatedAt: 1_000
            )],
            executions: [], claims: [], dependencies: [], events: [], generatedAt: 1_000
        )
        let taskKey = AppModel.invocationTaskKey(projectId, taskId)
        let requestId = "request-1"
        model.invocationPendingRooms[requestId] = "\(taskKey)\u{1f}room-1"
        let page = ProjectInvocationPage(
            type: "mesh.invocation.page", sessionId: projectId, projectId: projectId,
            taskId: taskId, requestId: requestId, sourceEndpointId: "computer-1",
            availability: "ready", events: [.init(sequence: 2, event: event(phase: "requested"))],
            nextSequence: 2, previousSequence: 2, hasMore: false, hasOlder: true,
            generatedAt: 2_000
        )
        model.receiveInvocationPage(page, fromRoom: "room-2")
        XCTAssertNil(model.invocationHistoryByTask[taskKey])
        XCTAssertNotNil(model.invocationPendingRooms[requestId])

        model.receiveInvocationPage(page, fromRoom: "room-1")
        XCTAssertEqual(model.invocationHistoryByTask[taskKey]?.count, 1)
        XCTAssertEqual(model.invocationAvailabilityByTask[taskKey], "ready")
        XCTAssertTrue(model.hasOlderInvocations(projectId: projectId, taskId: taskId))
        XCTAssertNil(model.invocationPendingRooms[requestId])

        model.receiveInvocationPage(page, fromRoom: "room-1")
        XCTAssertEqual(model.invocationHistoryByTask[taskKey]?.count, 1)
    }
}
