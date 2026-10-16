import XCTest
@testable import GrantTap

final class TaskHandoffOutcomeTests: XCTestCase {
    func testPreparationNeedsTheDestinationReceipt() {
        XCTAssertEqual(observe([request()]), .waiting)
        XCTAssertEqual(observe([request(), accepted()]), .prepared("destination"))
    }

    func testOldReceiptsAndOtherDestinationsCannotCompleteThisTransfer() {
        XCTAssertEqual(observe([request(), accepted()], previous: ["request", "accepted"]), .waiting)
        var other = request()
        other.payload.capsule = capsule(provider: "claude")
        XCTAssertEqual(observe([other, accepted()]), .waiting)
        other = request()
        other.payload.capsule = capsule(computer: "another-mac")
        XCTAssertEqual(observe([other, accepted()]), .waiting)
    }

    func testForgedOrUnrelatedReceiptsCannotCompleteThisTransfer() {
        var invalid = accepted()
        invalid.payload.receipt = .init(sourceSessionId: "source", targetSessionId: "destination",
            taskId: "task", capsuleHash: String(repeating: "0", count: 64), acceptedAt: 50)
        XCTAssertEqual(observe([request(), invalid]), .waiting)
        invalid.taskId = "another-task"
        XCTAssertEqual(observe([request(), invalid]), .waiting)
    }

    func testComputerFailureIsShownWithoutPretendingToPrepareAChat() {
        let blocked = event("blocked", "TASK_BLOCKED", source: "source", payload: .init(reason: "Dirty checkout"))
        XCTAssertEqual(observe([blocked]), .failed("Dirty checkout"))
        let rejected = event("rejected", "HANDOFF_REJECTED", source: "computer:mac", target: "source",
                             payload: .init(reason: "Worktree failed"))
        XCTAssertEqual(observe([request(), rejected]), .failed("Worktree failed"))
        XCTAssertEqual(observe([rejected]), .waiting)
    }

    func testUnrelatedMeshAndMissingSnapshotDoNotConfirmTransfer() {
        XCTAssertEqual(TaskHandoffOutcome.observe(session: session(), snapshot: nil,
            provider: "grok", computer: "mac", previousEvents: []), .waiting)
        var chat = session()
        chat.projectId = "another-project"
        XCTAssertEqual(TaskHandoffOutcome.observe(session: chat, snapshot: snapshot([request(), accepted()]),
            provider: "grok", computer: "mac", previousEvents: []), .waiting)
        XCTAssertEqual(TaskHandoffOutcome.observe(session: session(), snapshot: snapshot([request(), accepted()]),
            provider: "grok", computer: "mac", previousEvents: [], notBefore: 51), .waiting)
    }

    private func observe(_ events: [ProjectMeshEvent], previous: Set<String> = []) -> TaskHandoffOutcome {
        .observe(session: session(), snapshot: snapshot(events), provider: "grok", computer: "mac",
                 previousEvents: previous)
    }

    private func request() -> ProjectMeshEvent {
        event("request", "HANDOFF_REQUEST", source: "source", payload: .init(capsule: capsule()))
    }

    private func accepted() -> ProjectMeshEvent {
        let receipt = ProjectHandoffReceipt(prepared: true, sourceSessionId: "source",
            targetSessionId: "destination", taskId: "task",
            capsuleHash: ProjectMeshReceiptValidator.capsuleHash(capsule())!, acceptedAt: 50)
        return event("accepted", "HANDOFF_ACCEPTED", source: "destination", target: "source",
                     payload: .init(receipt: receipt))
    }

    private func event(_ id: String, _ type: String, source: String, target: String? = nil,
                       payload: ProjectMeshEventPayload) -> ProjectMeshEvent {
        .init(type: "mesh.event", sessionId: "task", eventId: id, projectId: "project",
              taskId: "task", sourceSessionId: source, targetSessionId: target,
              eventType: type, createdAt: 50, payload: payload)
    }

    private func capsule(provider: String = "grok", computer: String = "mac") -> TaskCapsule {
        .init(taskId: "task", goal: "Existing work", currentStatus: "idle", sourceProvider: "codex",
              sourceComputer: "mac", targetProvider: provider, targetComputer: computer,
              repository: "repo", baseSha: String(repeating: "a", count: 40),
              filesChanged: [], dependencies: [], resourceClaims: [], remainingWork: [],
              importantDecisions: [], createdAt: 40)
    }

    private func session() -> SessionInfo {
        .init(sessionId: "source", agent: "codex", projectId: "project", taskId: "task",
              computerId: "mac", model: nil, state: "idle", startedAt: 1, lastActivityAt: 30,
              tokensSession: 0, tokensLastTurn: 0)
    }

    private func snapshot(_ events: [ProjectMeshEvent]) -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: "project", projectId: "project",
              project: .init(projectId: "project", name: "Project", canonicalRepositoryId: "repo", createdAt: 1),
              tasks: [], executions: [], claims: [], dependencies: [], events: events, generatedAt: 60)
    }
}
