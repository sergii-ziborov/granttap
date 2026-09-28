import SwiftUI
import UIKit
import XCTest
import TweetNacl
@testable import GrantTap

@MainActor
final class ProjectMeshRuntimeTests: XCTestCase {
    let now = 1_800_000_000_000.0

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
    }

    override func tearDown() {
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    func testMergePrunesExpiredStateAndDeduplicatesEvents() {
        var current = snapshot(generatedAt: now)
        current.claims = [claim(expiresAt: now - 1)]
        current.events = [event(id: "same", type: "TASK_PROGRESS", payload: .init(summary: "old"))]
        var incoming = snapshot(generatedAt: now + 1)
        incoming.executions.append(execution(session: "codex", provider: "codex", computer: "PC"))
        incoming.events = [
            event(id: "same", type: "TASK_PROGRESS", payload: .init(summary: "new")),
            event(id: "expired", type: "TASK_PROGRESS", expiresAt: now - 1,
                  payload: .init(summary: "expired")),
        ]
        let merged = ProjectMeshLogic.merged(current: current, incoming: incoming, nowMs: now)
        XCTAssertEqual(merged.executions.count, 2)
        XCTAssertTrue(merged.claims.isEmpty)
        XCTAssertEqual(merged.events.map(\.eventId), ["same"])
        XCTAssertEqual(merged.events[0].payload.summary, "new")
    }

    func testAppModelRoutesMeshNeedsYouWithoutDuplicatingTechnicalQuestions() {
        let model = AppModel()
        model.meshSnapshots = [:]
        model.pendingMeshEvents = []
        model.receive(snapshot(generatedAt: now), fromRoom: "source")
        let product = event(
            id: "product", type: "AGENT_QUESTION",
            payload: .init(question: "Choose behavior", category: "product")
        )
        model.receive(product, fromRoom: "source")
        XCTAssertEqual(model.meshNeedsYouEvents.map(\.eventId), ["product"])
        XCTAssertEqual(model.humanAttentionItems.map(\.id), ["product"])
        XCTAssertEqual(model.humanAttentionItems.first?.action, .meshReply)
        XCTAssertEqual(model.meshEvents(forTaskId: "task").map(\.eventId), ["product"])

        let technical = event(
            id: "technical", type: "AGENT_QUESTION", targetSessionId: "codex",
            payload: .init(question: "Field name?", category: "technical")
        )
        model.receive(technical, fromRoom: "source")
        XCTAssertEqual(model.meshNeedsYouEvents.map(\.eventId), ["product"])
        model.dismissMeshEvent("product")
        XCTAssertTrue(model.meshNeedsYouEvents.isEmpty)
        XCTAssertEqual(model.meshSnapshot(for: "project")?.events.count, 2)
    }

    func testLocallyAuthorizedHandoffSkipsSecondNeedsYouPrompt() {
        let model = AppModel()
        model.meshSnapshots = ["project": snapshot(generatedAt: now)]
        model.pendingMeshEvents = []
        model.authorizedHandoffRoutes["task"] = "codex\u{1f}Workstation"
        let handoff = event(
            id: "handoff", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        model.receive(handoff, fromRoom: "source")
        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        XCTAssertNil(model.authorizedHandoffRoutes["task"])

        let manual = event(
            id: "manual", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        model.receive(manual, fromRoom: "source")
        XCTAssertEqual(model.pendingMeshEvents.map(\.eventId), ["manual"])
    }

    func testMeshPersistenceRoundTripsProtectedBoundedState() {
        let archive = ProjectMeshArchive(
            snapshots: ["project": snapshot(generatedAt: now)],
            pendingEvents: [event(id: "pending", type: "CONFLICT",
                                  payload: .init(resource: "src/auth/**", resolved: false))]
        )
        ProjectMeshPersistence.save(archive)
        let restored = ProjectMeshPersistence.load()
        XCTAssertEqual(restored.snapshots["project"]?.project.name, "GrantTap")
        XCTAssertEqual(restored.pendingEvents.map(\.eventId), ["pending"])
        ProjectMeshPersistence.clear()
        XCTAssertTrue(ProjectMeshPersistence.load().snapshots.isEmpty)

        let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("GrantTap", isDirectory: true)
        let blockedFile = root.appendingPathComponent("project-mesh.json", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: blockedFile, withIntermediateDirectories: true
        )
        ProjectMeshPersistence.save(archive)
        try? FileManager.default.removeItem(at: blockedFile)
    }

    func testForwardedScopeKeysFailClosedAndNeverChangePairingScope() {
        let client = RelayClient(pairing: pairing(room: "target-room"))
        let scope = "task-\(UUID().uuidString)"
        XCTAssertFalse(client.installForwardedScopeKey("bad", scopeId: scope))
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        var invalidPurposeError: Error?
        // A purpose the wire does not know is refused before any key is kept.
        client.forwardMesh(event(id: "event", type: "TASK_PROGRESS",
                                 payload: .init(summary: "progress")),
                           scopeId: scope, key: key, purpose: "everything") {
            invalidPurposeError = $0
        }
        XCTAssertNotNil(invalidPurposeError)
        XCTAssertNil(client.sessionKey(for: scope))

        _ = client.installForwardedScopeKey(key, scopeId: scope)
        XCTAssertEqual(client.sessionKey(for: scope), key)
        XCTAssertEqual(client.pairing.room, "target-room")
        var deliveryError: Error?
        let scoped = ProjectMeshEvent(
            type: "mesh.event", sessionId: scope, eventId: "post-grant",
            projectId: "project", taskId: scope, sourceSessionId: "claude",
            targetSessionId: nil, eventType: "TASK_PROGRESS", createdAt: now,
            expiresAt: now + 60_000, payload: .init(summary: "ok")
        )
        client.sendForwardedMeshPayload(
            scoped, scopeId: scope, ttl: 60, grantError: nil
        ) { deliveryError = $0 }
        XCTAssertNotNil(deliveryError)
    }

    @MainActor func testMeshViewsBuildAllCuratedVariants() {
        let handoff = event(
            id: "handoff", type: "HANDOFF_REQUEST",
            payload: .init(capsule: capsule(targetComputer: "Workstation"))
        )
        _ = ProjectMeshNeedsYouCard(event: handoff, onAuthorize: {}, onOpen: {}, onDismiss: {}).body
        for type in [
            "HANDOFF_REQUEST", "HANDOFF_ACCEPTED", "HANDOFF_REJECTED", "AGENT_QUESTION",
            "AGENT_ANSWER", "TASK_BLOCKED", "TASK_COMPLETED", "RESOURCE_CLAIM", "CONFLICT",
            "TASK_PROGRESS",
        ] {
            _ = ProjectMeshTimelineRow(event: event(
                id: type, type: type,
                payload: .init(summary: "summary", reason: "reason", resource: "src/**")
            )).body
        }
        RenderProbe.render(CompatNavigationStack { ProjectMeshView(snapshot: snapshot(generatedAt: now), model: AppModel()) })
        let state = snapshot(generatedAt: now)
        _ = ProjectMeshTaskRow(task: state.tasks[0], execution: state.executions[0]).body
        _ = ProjectMeshTaskRow(task: state.tasks[0], execution: nil).body
        RenderProbe.render(TaskHandoffSheet(session: session(), model: AppModel()))
        let needsYou = ProjectMeshNeedsYouCard(
            event: event(id: "blocked", type: "TASK_BLOCKED",
                         payload: .init(reason: "Blocked", resource: "src/**")),
            onAuthorize: {}, onOpen: {}, onDismiss: {}
        )
        XCTAssertEqual(needsYou.eyebrow, "Blocked task")
        XCTAssertEqual(needsYou.title, "Blocked")
        XCTAssertEqual(needsYou.detail, "src/**")
        _ = needsYou.body
        let resourceRow = ProjectMeshTimelineRow(
            event: event(id: "resource", type: "CONFLICT", payload: .init(resource: "src/**"))
        )
        XCTAssertEqual(resourceRow.detail, "src/**")
        XCTAssertEqual(resourceRow.icon, "exclamationmark.triangle")
        XCTAssertEqual(resourceRow.label, "Conflict detected")
        let botExecution = ExecutionSessionLink(
            taskId: "task", sessionId: "bot", provider: "grok_bot", actorId: "qa-bot",
            computerId: "grok-cloud", workspace: "/repo", startedAt: now
        )
        XCTAssertEqual(MeshActorPresentation.executionName(botExecution), "QA Bot · Grok Bot")
    }

    func testMeshScreensRenderPopulatedProjectAndHandoffDestinations() throws {
        let model = AppModel()
        let source = try securePairing(room: "source-ui", device: "MacBook")
        let target = try securePairing(room: "target-ui", device: "Workstation")
        model.connectionRegistry = ConnectionRegistry(connections: [
            linked(source, machine: "MacBook"),
            linked(target, machine: "Workstation"),
        ], preferredId: source.room)
        model.sessionSourceRooms["claude"] = [source.room]

        var populated = snapshot(generatedAt: now)
        populated.tasks.append(.init(
            taskId: "tests", projectId: "project", title: "Integration tests",
            goal: "Verify handoff", state: "blocked", ownerSessionId: "codex",
            createdAt: now, updatedAt: now
        ))
        populated.executions.append(execution(
            session: "codex", provider: "codex", computer: "Workstation"
        ))

        render(ProjectMeshView(snapshot: populated, model: model))
        render(TaskHandoffSheet(session: session(), model: model))
    }

    private func render<Content: View>(_ view: Content) {
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.beginAppearanceTransition(true, animated: false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        host.endAppearanceTransition()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let size = host.sizeThatFits(in: CGSize(width: 390, height: 844))
        XCTAssertGreaterThan(size.height, 0)
    }

    func snapshot(generatedAt: Double) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/example/granttap",
                           baseRemote: nil, createdAt: now),
            tasks: [.init(taskId: "task", projectId: "project", title: "Pairing", goal: "Refactor",
                          state: "working", ownerSessionId: "claude", createdAt: now, updatedAt: now)],
            executions: [execution(session: "claude", provider: "claude", computer: "MacBook")],
            claims: [], dependencies: [], events: [], generatedAt: generatedAt
        )
    }

    func execution(session: String, provider: String, computer: String) -> ExecutionSessionLink {
        .init(taskId: "task", sessionId: session, provider: provider, computerId: computer,
              workspace: "/repo", branch: "branch", worktree: "/repo",
              uncommitted: false, updatedAt: now, startedAt: now, endedAt: nil)
    }

    private func claim(expiresAt: Double) -> ProjectResourceClaim {
        let value = ProjectResourceClaim(
            claimId: "claim", projectId: "project", taskId: "task", ownerSessionId: "claude",
            resource: "src/**", mode: "claim", createdAt: now, expiresAt: expiresAt
        )
        _ = value.id
        return value
    }

    func event(
        id: String, type: String, targetSessionId: String? = nil,
        expiresAt: Double? = nil, payload: ProjectMeshEventPayload,
        sourceSessionId: String = "claude"
    ) -> ProjectMeshEvent {
        .init(type: "mesh.event", sessionId: "task", eventId: id, projectId: "project",
              taskId: "task", sourceSessionId: sourceSessionId, targetSessionId: targetSessionId,
              eventType: type, createdAt: now, expiresAt: expiresAt ?? now + 60_000, payload: payload)
    }

    func capsule(targetComputer: String) -> TaskCapsule {
        .init(taskId: "task", goal: "Refactor", currentStatus: "Ready", sourceProvider: "claude",
              sourceComputer: "MacBook", targetProvider: "codex", targetComputer: targetComputer,
              repository: "github.com/example/granttap", baseSha: String(repeating: "a", count: 40),
              branch: "claude/pairing", latestCommit: nil, dirtyDiffHash: nil, filesChanged: [],
              testsStatus: nil, dependencies: [], resourceClaims: [], remainingWork: ["Test"],
              importantDecisions: [], createdAt: now)
    }

    func session() -> SessionInfo {
        .init(sessionId: "claude", agent: "claude", projectId: "project", taskId: "task",
              computerId: "MacBook", title: "Pairing", cwd: "/repo", branch: "branch",
              worktree: "/repo", model: nil, summary: nil, accessLevel: nil, state: "idle",
              startedAt: now, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
    }

    private func pairing(room: String) -> Pairing {
        .init(relayUrl: "ws://127.0.0.1:1", room: room, role: "phone", deviceName: "iPhone",
              senderId: "phone", myPublicKey: "public", mySecretKey: "secret",
              peerPublicKey: "peer")
    }

    func securePairing(room: String, device: String) throws -> Pairing {
        let phone = try NaclBox.keyPair()
        let machine = try NaclBox.keyPair()
        return .init(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone", deviceName: device,
            senderId: "phone", myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString()
        )
    }

    func linked(_ pairing: Pairing, machine: String) -> LinkedComputer {
        .init(id: pairing.room, pairing: pairing, label: "", addedAt: now,
              lastCatalogAt: now, lastMachineName: machine)
    }
}
