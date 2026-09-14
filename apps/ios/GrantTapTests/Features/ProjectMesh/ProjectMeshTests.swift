import XCTest
@testable import GrantTap

final class ProjectMeshTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    func testHumanAttentionIsNarrowAndDeterministic() {
        XCTAssertFalse(ProjectMeshLogic.needsHuman(type: "AGENT_QUESTION", payload: .init(
            question: "Which field name?", category: "technical"
        )))
        XCTAssertTrue(ProjectMeshLogic.needsHuman(type: "AGENT_QUESTION", payload: .init(
            question: "Which product behavior?", category: "product"
        )))
        XCTAssertFalse(ProjectMeshLogic.needsHuman(type: "CONFLICT", payload: .init(
            resource: "src/auth/**", resolved: false, needsUser: false
        )))
        XCTAssertTrue(ProjectMeshLogic.needsHuman(type: "CONFLICT", payload: .init(
            resource: "src/auth/**", resolved: false, needsUser: true
        )))
        XCTAssertFalse(ProjectMeshLogic.needsHuman(type: "TASK_BLOCKED", payload: .init(
            reason: "Waiting for another task", needsUser: false
        )))
        XCTAssertTrue(ProjectMeshLogic.needsHuman(type: "HANDOFF_REJECTED", payload: .init(
            reason: "Target failed", failed: true
        )))
    }

    func testTaskIdentitySurvivesHandoffExecutions() {
        let snapshot = fixtureSnapshot()
        let task = snapshot.tasks[0]
        XCTAssertEqual(Set(snapshot.executions.map(\.taskId)), [task.taskId])
        XCTAssertEqual(snapshot.executions.map(\.provider), ["claude", "codex"])
        XCTAssertEqual(ProjectMeshLogic.visibleProject(snapshot), true)
        XCTAssertEqual(snapshot.project.id, "project")
        XCTAssertEqual(task.id, "task")
        XCTAssertEqual(snapshot.executions[0].id, "MacBook\u{1f}claude\u{1f}claude-native")
        XCTAssertEqual(snapshot.id, "project")
        let dependency = ProjectTaskDependency(
            taskId: "task", dependsOnTaskId: "api", summary: nil, createdAt: now
        )
        XCTAssertEqual(dependency.id, "task\u{1f}api")
        XCTAssertEqual(fixtureEvent(targetSessionId: nil, targetComputer: "PC").id, "event")
    }

    func testExplicitDestinationNeverBroadcasts() {
        let event = fixtureEvent(targetSessionId: nil, targetComputer: "Workstation")
        let room = ProjectMeshLogic.destinationRoom(
            for: event,
            sessionRooms: ["claude-native": "room-source"],
            computerRooms: ["MacBook": "room-source", "Workstation": "room-target"]
        )
        XCTAssertEqual(room, "room-target")
        XCTAssertNil(ProjectMeshLogic.destinationRoom(
            for: fixtureEvent(targetSessionId: nil, targetComputer: "Unknown"),
            sessionRooms: [:], computerRooms: [:]
        ))
    }

    func testWireValidatorRejectsHiddenReasoningAndOversizedCapsule() throws {
        let valid = try JSONEncoder().encode(fixtureEvent(targetSessionId: "codex-native",
                                                          targetComputer: "Workstation"))
        XCTAssertTrue(ProjectMeshWireValidator.validEvent(valid))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var payload = try XCTUnwrap(object["payload"] as? [String: Any])
        var capsule = try XCTUnwrap(payload["capsule"] as? [String: Any])
        capsule["hiddenReasoning"] = "private chain"
        payload["capsule"] = capsule
        object["payload"] = payload
        XCTAssertFalse(ProjectMeshWireValidator.validEvent(
            try JSONSerialization.data(withJSONObject: object)
        ))
        capsule.removeValue(forKey: "hiddenReasoning")
        capsule["importantDecisions"] = Array(repeating: "fact", count: 17)
        payload["capsule"] = capsule
        object["payload"] = payload
        XCTAssertFalse(ProjectMeshWireValidator.validEvent(
            try JSONSerialization.data(withJSONObject: object)
        ))
        let progress = ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "progress", projectId: "project",
            taskId: "task", sourceSessionId: "claude-native", targetSessionId: nil,
            eventType: "TASK_PROGRESS", createdAt: now, expiresAt: now + 60_000,
            payload: .init(summary: "Working")
        )
        XCTAssertTrue(ProjectMeshWireValidator.validEvent(try JSONEncoder().encode(progress)))
    }

    func testWireValidatorBoundsProjectSnapshots() throws {
        let encoded = try JSONEncoder().encode(fixtureSnapshot())
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(encoded))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["events"] = Array(repeating: ["type": "mesh.event"], count: 129)
        XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(
            try JSONSerialization.data(withJSONObject: object)
        ))
        object["events"] = [["not": "an event"]]
        XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(
            try JSONSerialization.data(withJSONObject: object)
        ))
    }

    func testIntegrationPeersDecodeAdditivelyAndStayProjectScoped() throws {
        let legacy = try JSONEncoder().encode(fixtureSnapshot())
        XCTAssertNil(try JSONDecoder().decode(ProjectMeshSnapshot.self, from: legacy).peers)

        var current = fixtureSnapshot()
        current.peers = [ProjectIntegrationPeer(
            projectId: "project", repositoryId: "github.com/example/frontend", peer: "backend",
            via: "api", relation: "calls", updatedAt: 1
        )]
        let encoded = try JSONEncoder().encode(current)
        XCTAssertEqual(try JSONDecoder().decode(ProjectMeshSnapshot.self, from: encoded).peers?.first?.peer,
                       "backend")
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(encoded))

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var peers = try XCTUnwrap(object["peers"] as? [[String: Any]])
        func valid() throws -> Bool {
            object["peers"] = peers
            return ProjectMeshWireValidator.validSnapshot(try JSONSerialization.data(withJSONObject: object))
        }
        peers[0]["projectId"] = "other-project"
        XCTAssertFalse(try valid(), "a peer stays Project scoped")
        peers[0]["projectId"] = "project"
        peers[0]["via"] = "carrier-pigeon"
        XCTAssertFalse(try valid(), "only the map's own kinds of edge")
        peers[0]["via"] = "api"
        peers[0]["secret"] = "x"
        XCTAssertFalse(try valid(), "no extra keys")
        peers[0]["secret"] = nil
        XCTAssertTrue(try valid())

        // Each computer states its own checkouts; the phone keeps the union.
        var incoming = current
        incoming.peers = [ProjectIntegrationPeer(
            projectId: "project", repositoryId: "github.com/example/backend", peer: "frontend",
            via: "api", relation: "called_by", updatedAt: 1
        )]
        XCTAssertEqual(ProjectMeshLogic.merged(current: current, incoming: incoming, nowMs: 2).peers?.count, 2)
        XCTAssertNil(ProjectMeshLogic.merged(current: fixtureSnapshot(), incoming: fixtureSnapshot(), nowMs: 2).peers)
    }

    func testProjectBindingsDecodeAdditivelyAndStayProjectScoped() throws {
        let legacy = try JSONEncoder().encode(fixtureSnapshot())
        XCTAssertNil(try JSONDecoder().decode(ProjectMeshSnapshot.self, from: legacy).bindings)

        var current = fixtureSnapshot()
        current.bindings = [ProjectBindingSummary(
            bindingId: "mac-frontend", projectId: "project", endpointId: "MacBook",
            repositoryId: "github.com/example/frontend", displayName: "Frontend",
            available: true, revision: String(repeating: "a", count: 40)
        )]
        let encoded = try JSONEncoder().encode(current)
        let decoded = try JSONDecoder().decode(ProjectMeshSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.bindings?.first?.id, "mac-frontend")
        XCTAssertNil(decoded.bindings?.first?.localPathHint)
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(encoded))

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var bindings = try XCTUnwrap(object["bindings"] as? [[String: Any]])
        bindings[0]["projectId"] = "other-project"
        object["bindings"] = bindings
        XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(
            try JSONSerialization.data(withJSONObject: object)
        ))
        bindings[0]["projectId"] = "project"
        bindings.append(bindings[0])
        object["bindings"] = bindings
        XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(
            try JSONSerialization.data(withJSONObject: object)
        ))
    }

    func testHandoffReceiptAuthenticatesTheExactCapsule() {
        let request = fixtureEvent(targetSessionId: nil, targetComputer: "Workstation")
        var snapshot = fixtureSnapshot()
        snapshot.events = [request]
        let receipt = ProjectHandoffReceipt(
            sourceSessionId: "claude-native", targetSessionId: "codex-native", taskId: "task",
            capsuleHash: "c08dd225f5d7364191af2e8fda8f74191af2b5b4c2b3e59b0cdca133fce14b05",
            acceptedAt: now + 1
        )
        let accepted = ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "accepted", projectId: "project",
            taskId: "task", sourceSessionId: "codex-native", targetSessionId: "claude-native",
            eventType: "HANDOFF_ACCEPTED", createdAt: now + 1, expiresAt: now + 60_000,
            payload: .init(receipt: receipt)
        )
        XCTAssertEqual(ProjectMeshReceiptValidator.capsuleHash(request.payload.capsule!),
                       receipt.capsuleHash)
        XCTAssertTrue(ProjectMeshReceiptValidator.valid(receipt, for: accepted, in: snapshot))
        let forged = ProjectHandoffReceipt(
            sourceSessionId: receipt.sourceSessionId, targetSessionId: receipt.targetSessionId,
            taskId: receipt.taskId, capsuleHash: String(repeating: "0", count: 64), acceptedAt: now + 1
        )
        XCTAssertFalse(ProjectMeshReceiptValidator.valid(forged, for: accepted, in: snapshot))
    }

    private func fixtureSnapshot() -> ProjectMeshSnapshot {
        let project = ProjectMeshProject(
            projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
            canonicalRepositoryId: "github.com/example/granttap", baseRemote: nil, createdAt: now
        )
        let task = ProjectMeshTask(
            taskId: "task", projectId: "project", title: "Pairing refactor", goal: "Refactor pairing",
            state: "working", ownerSessionId: "codex-native", createdAt: now, updatedAt: now
        )
        let source = ExecutionSessionLink(
            taskId: "task", sessionId: "claude-native", provider: "claude", computerId: "MacBook",
            workspace: "/repo", branch: "claude/pairing", worktree: "/repo", startedAt: now, endedAt: now
        )
        let target = ExecutionSessionLink(
            taskId: "task", sessionId: "codex-native", provider: "codex", computerId: "Workstation",
            workspace: "/repo-tests", branch: "codex/tests", worktree: "/repo-tests",
            startedAt: now + 1, endedAt: nil
        )
        return ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project", project: project,
            tasks: [task], executions: [source, target], claims: [], dependencies: [], events: [],
            generatedAt: now
        )
    }

    private func fixtureEvent(targetSessionId: String?, targetComputer: String) -> ProjectMeshEvent {
        let capsule = TaskCapsule(
            taskId: "task", goal: "Refactor pairing", currentStatus: "Crypto complete",
            sourceProvider: "claude", sourceComputer: "MacBook", targetProvider: "codex",
            targetComputer: targetComputer, repository: "github.com/example/granttap",
            baseSha: String(repeating: "a", count: 40), branch: "claude/pairing", latestCommit: nil,
            dirtyDiffHash: nil, filesChanged: [], testsStatus: nil, dependencies: [], resourceClaims: [],
            remainingWork: ["Run tests"], importantDecisions: [], createdAt: now
        )
        return ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "event", projectId: "project",
            taskId: "task", sourceSessionId: "claude-native", targetSessionId: targetSessionId,
            eventType: "HANDOFF_REQUEST", createdAt: now, expiresAt: now + 60_000,
            payload: .init(capsule: capsule)
        )
    }
}
