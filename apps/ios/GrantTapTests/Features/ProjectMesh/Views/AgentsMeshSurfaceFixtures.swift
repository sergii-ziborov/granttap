import SwiftUI
import XCTest
@testable import GrantTap

/// Deterministic Grok Bot / Project Mesh fixtures shared by the surface tests.
@MainActor
extension AgentsMeshSurfaceCoverageTests {
    func connection(status: String) -> GrokBotEndpointConnection {
        let actors = [
            actor(id: "qa-bot", name: "QA Bot", enabled: true),
            actor(id: "research-bot", name: "Research Bot", enabled: true),
            actor(id: "release-bot", name: "Release Bot", enabled: false),
        ]
        return .init(
            version: 1,
            endpoint: .init(endpointId: "endpoint", kind: "grok_bot_cloud",
                            displayName: "Grok Bot Cloud", publicKey: "key",
                            credentialId: "credential", status: status, createdAt: 1),
            credential: .init(credentialId: "credential", endpointId: "endpoint", status: "active",
                              projectIds: ["project"], taskIds: ["task"],
                              operations: ["progress"], issuedAt: 1, expiresAt: 4_000_000_000_000),
            actors: actors, phonePairing: pairing(room: "bot-room"),
            policy: .init(type: "mesh.endpoint.policy", endpointId: "endpoint",
                          credentialId: "credential", enabled: true, status: "active",
                          projectIds: ["project"],
                          actors: actors.map { .init(actorId: $0.actorId, enabled: $0.enabled) },
                          revision: 1, createdAt: 1),
            inviteExpiresAt: 4_000_000_000_000
        )
    }

    func actor(id: String, name: String, enabled: Bool) -> GrokBotMeshActor {
        .init(actorId: id, endpointId: "endpoint", kind: "persistent_agent",
              displayName: name, status: "idle", enabled: enabled)
    }

    func pairing(room: String) -> Pairing {
        .init(relayUrl: "wss://relay.granttap.ai", room: room, role: "phone",
              deviceName: "Device", senderId: "phone", myPublicKey: "a",
              mySecretKey: "b", peerPublicKey: "c", pushAuth: "d")
    }

    func linked(room: String, machine: String) -> LinkedComputer {
        .init(id: room, pairing: pairing(room: room), label: "Workstation", addedAt: 1,
              lastCatalogAt: 1, lastMachineName: machine)
    }

    func session(
        id: String, provider: String, projectId: String? = nil, taskId: String? = nil
    ) -> SessionInfo {
        .init(sessionId: id, agent: provider, projectId: projectId, taskId: taskId,
              title: id, state: "working", startedAt: 1, lastActivityAt: 1,
              tokensSession: 0, tokensLastTurn: 0)
    }

    func approval(provider: String) -> ApprovalRequest {
        .init(type: "approval.request", requestId: "approval", agent: provider,
              kind: "permission", tool: "Shell", title: "Run", command: nil, cwd: nil,
              sessionId: "live", risk: .medium, danger: nil, createdAt: 1)
    }

    func question(sessionId: String) -> AgentEvent {
        .init(type: "agent.event", text: "Continue?", requestId: UUID().uuidString,
              kind: "question", sessionId: sessionId, createdAt: 1)
    }

    func snapshot() -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: "project", projectId: "project",
              project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                             canonicalRepositoryId: "repo", createdAt: 1),
              tasks: [.init(taskId: "task", projectId: "project", title: "Task", goal: "Goal",
                            state: "working", ownerSessionId: "source-session",
                            createdAt: 1, updatedAt: 1)],
              executions: [], claims: [], dependencies: [], events: [], generatedAt: 1)
    }

    func snapshotWithGrokClaim() -> ProjectMeshSnapshot {
        var value = snapshot()
        value.executions = [.init(taskId: "task", sessionId: "grok-session",
                                  provider: "grok_bot", actorId: "qa-bot",
                                  computerId: "grok-cloud", workspace: "/repo", startedAt: 1)]
        value.claims = [.init(claimId: "claim", projectId: "project", taskId: "task",
                              ownerSessionId: "grok-session", resource: "tests/**",
                              mode: "claim", createdAt: 1, expiresAt: 100)]
        return value
    }

    func handoffSnapshot(resolved: Bool) -> ProjectMeshSnapshot {
        var value = snapshot()
        let capsule = TaskCapsule(taskId: "task", goal: "Goal", currentStatus: "working",
                                  sourceProvider: "claude", sourceComputer: "MacBook",
                                  targetProvider: "cursor", targetComputer: "Workstation",
                                  repository: "repo", baseSha: "abc", filesChanged: [],
                                  testsStatus: "unknown", dependencies: [], resourceClaims: [],
                                  remainingWork: ["Continue"], importantDecisions: [], createdAt: 1)
        value.events = [.init(type: "mesh.event", sessionId: "task", eventId: "request",
                              projectId: "project", taskId: "task", sourceSessionId: "source",
                              eventType: "HANDOFF_REQUEST", createdAt: 1,
                              payload: .init(capsule: capsule))]
        if resolved {
            value.events.append(.init(type: "mesh.event", sessionId: "task", eventId: "accepted",
                                      projectId: "project", taskId: "task",
                                      sourceSessionId: "target", eventType: "HANDOFF_ACCEPTED",
                                      createdAt: 2, payload: .init()))
        }
        return value
    }
}
