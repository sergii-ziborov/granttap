import SwiftUI
import XCTest
@testable import GrantTap

/// One Task, its execution, the snapshot they arrive in, and the capsule and
/// receipt a hand-off is made of.
@MainActor
enum ProjectMeshConvergenceFixtures {
    static let now = 1_800_000_000_000.0

    static func task() -> ProjectMeshTask {
        .init(taskId: "task", projectId: "project", title: "Pairing", goal: "Refactor",
              state: "working", ownerSessionId: "claude", createdAt: now, updatedAt: now)
    }

    static func execution() -> ExecutionSessionLink {
        .init(taskId: "task", sessionId: "claude", provider: "claude", computerId: "MacBook",
              workspace: "/repo", branch: "claude/pairing", worktree: "/repo",
              uncommitted: false, updatedAt: now, startedAt: now, endedAt: nil)
    }

    static func snapshot(generatedAt: Double) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/example/granttap",
                           baseRemote: nil, createdAt: now),
            tasks: [task()], executions: [execution()],
            claims: [], dependencies: [], events: [], generatedAt: generatedAt
        )
    }

    static func capsule(targetProvider: String) -> TaskCapsule {
        .init(taskId: "task", goal: "Refactor", currentStatus: "Ready", sourceProvider: "claude",
              sourceComputer: "MacBook", targetProvider: targetProvider,
              targetComputer: "Workstation", repository: "github.com/example/granttap",
              baseSha: String(repeating: "a", count: 40), branch: "claude/pairing",
              latestCommit: nil, dirtyDiffHash: nil, workingTree: "clean", filesChanged: [],
              testsStatus: nil, dependencies: [], resourceClaims: [], remainingWork: ["Test"],
              importantDecisions: [], createdAt: now)
    }

    static func request(id: String, capsule: TaskCapsule) -> ProjectMeshEvent {
        .init(type: "mesh.event", sessionId: "task", eventId: id, projectId: "project",
              taskId: "task", sourceSessionId: "claude", targetSessionId: nil,
              eventType: "HANDOFF_REQUEST", createdAt: now, expiresAt: now + 600_000,
              payload: .init(capsule: capsule))
    }

    static func accepted(
        id: String, targetProvider: String, target: String, at acceptedAt: Double
    ) throws -> ProjectMeshEvent {
        let hash = try XCTUnwrap(
            ProjectMeshReceiptValidator.capsuleHash(capsule(targetProvider: targetProvider))
        )
        let receipt = ProjectHandoffReceipt(
            sourceSessionId: "claude", targetSessionId: target, taskId: "task",
            capsuleHash: hash, acceptedAt: acceptedAt
        )
        return .init(type: "mesh.event", sessionId: "task", eventId: id, projectId: "project",
                     taskId: "task", sourceSessionId: target, targetSessionId: "claude",
                     eventType: "HANDOFF_ACCEPTED", createdAt: acceptedAt,
                     expiresAt: acceptedAt + 600_000, payload: .init(receipt: receipt))
    }

    static func session() -> SessionInfo {
        .init(sessionId: "claude", agent: "claude", projectId: "project", taskId: "task",
              computerId: "MacBook", title: "Pairing", cwd: "/repo", branch: "claude/pairing",
              worktree: "/repo", state: "working", startedAt: now, lastActivityAt: now,
              tokensSession: 10, tokensLastTurn: 2)
    }
}
