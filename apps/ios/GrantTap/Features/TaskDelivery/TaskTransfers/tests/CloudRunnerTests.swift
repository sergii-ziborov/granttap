import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class CloudRunnerTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    private func session() -> SessionInfo {
        SessionInfo(sessionId: "chat", agent: "claude", projectId: "project", taskId: "task", title: "Pairing",
                    cwd: "/repo", branch: "main", state: "idle", startedAt: now - 1_000, lastActivityAt: now,
                    tokensSession: 1, tokensLastTurn: 1)
    }

    private func snapshot(executions: [ExecutionSessionLink] = [], events: [ProjectMeshEvent] = []) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/example/granttap", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Pairing", goal: "g", state: "working",
                          ownerSessionId: "chat", createdAt: 1, updatedAt: 2)],
            executions: executions, claims: [], dependencies: [], events: events, generatedAt: now
        )
    }

    private func cloudRun(startedAt: Double, url: String? = "https://claude.ai/code/cse_1") -> ExecutionSessionLink {
        ExecutionSessionLink(taskId: "task", sessionId: "cse_1", provider: "claude", computerId: "mac.lan",
                             workspace: "/repo", branch: "main", startedAt: startedAt, endedAt: nil,
                             external: ExternalExecution(runner: "claude_cloud", url: url))
    }

    func testACloudDestinationIsATagThatNoComputerRoomCanBe() {
        let target = TaskHandoffCloudTarget(provider: "codex", room: "room-1")
        XCTAssertEqual(TaskHandoffCloudTarget(tag: target.tag), target)
        XCTAssertNil(TaskHandoffCloudTarget(tag: "room-1"))
        XCTAssertNil(TaskHandoffCloudTarget(tag: "cloud\u{1f}grok\u{1f}room-1"), "only Claude and Codex have runners")
        XCTAssertNil(TaskHandoffCloudTarget(tag: "cloud\u{1f}claude\u{1f}"))
        XCTAssertEqual(target.label(computer: "MacBook"), "Codex Cloud · via MacBook")
        XCTAssertEqual(TaskHandoffCloudTarget(provider: "claude", room: "r").label(computer: "MacBook"), "Claude cloud · via MacBook")
    }

    func testOnlyAnInstalledCLIThatReportsItsCloudStartIsOffered() {
        let rows = [
            AgentIntegrationInfo(agent: "codex", installed: true, hookConfigured: true, cloud: true),
            AgentIntegrationInfo(agent: "claude", installed: false, hookConfigured: false, cloud: true),
            AgentIntegrationInfo(agent: "grok", installed: true, hookConfigured: false, cloud: true),
        ]
        XCTAssertEqual(TaskHandoffCloudTarget.available(in: rows), ["codex"])
        XCTAssertEqual(TaskHandoffCloudTarget.available(in: [
            AgentIntegrationInfo(agent: "claude", installed: true, hookConfigured: true),
        ]), [], "an older computer that says nothing offers nothing")
        let decoded = try? JSONDecoder().decode(AgentIntegrationInfo.self,
            from: Data(#"{"agent":"claude","installed":true,"hookConfigured":true,"cloud":true}"#.utf8))
        XCTAssertEqual(decoded?.cloud, true)
    }

    func testTheWireCarriesTheCloudRequestAndTheExternalRunBothWays() throws {
        let request = ProjectMeshHandoffPrepare(
            type: "mesh.handoff.prepare", sessionId: "chat", projectId: "project", taskId: "task",
            targetProvider: "codex", targetComputer: "mac.lan", createdAt: now, push: true, prepareOnly: true,
            cloud: ProjectMeshCloudLaunch(environment: "example/granttap"))
        let object = try JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(request)) as? [String: Any]
        XCTAssertEqual(object?["cloud"] as? [String: String], ["environment": "example/granttap"])
        let plain = ProjectMeshHandoffPrepare(type: "mesh.handoff.prepare", sessionId: "chat", projectId: "project",
            taskId: "task", targetProvider: "codex", targetComputer: "mac.lan", createdAt: now)
        let plainObject = try JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(plain)) as? [String: Any]
        XCTAssertNil(plainObject?["cloud"], "a computer transfer stays byte-for-byte what older computers accept")

        let wire = #"{"taskId":"task","sessionId":"task_e_1","provider":"codex","computerId":"mac.lan","workspace":"/repo","startedAt":1,"external":{"runner":"codex_cloud","url":"https://chatgpt.com/codex/tasks/task_e_1"}}"#
        let run = try JSONDecoder().decode(ExecutionSessionLink.self, from: Data(wire.utf8))
        XCTAssertEqual(run.external?.provider, "codex")
        XCTAssertEqual(run.external?.link?.host, "chatgpt.com")
        let old = #"{"taskId":"task","sessionId":"s","provider":"codex","computerId":"mac","workspace":"/repo","startedAt":1}"#
        XCTAssertNil(try JSONDecoder().decode(ExecutionSessionLink.self, from: Data(old.utf8)).external)
        XCTAssertNil(ExternalExecution(runner: "claude_cloud", url: "javascript:alert(1)").link)
        XCTAssertNil(ExternalExecution(runner: "claude_cloud", url: "http://claude.ai/code/x").link)
        XCTAssertEqual(ExecutionCoalescing.coalesced([run, run]).first?.external, run.external)
    }

    func testTheSheetSeesTheRunTheComputerRecordedOrItsRefusalAndNothingOlder() async {
        let target = TaskHandoffCloudTarget(provider: "claude", room: "source")
        func observe(_ snapshot: ProjectMeshSnapshot?) -> CloudHandoffOutcome {
            CloudHandoffOutcome.observe(session: session(), snapshot: snapshot, target: target,
                                        computer: "mac.lan", previousEvents: ["old"], notBefore: now)
        }
        XCTAssertEqual(observe(nil), .waiting)
        XCTAssertEqual(observe(snapshot(executions: [cloudRun(startedAt: now - 1)])), .waiting, "an earlier run is not this one")
        let run = cloudRun(startedAt: now + 5)
        XCTAssertEqual(observe(snapshot(executions: [run])), .started(run))
        func blocked(_ id: String) -> ProjectMeshEvent {
            ProjectMeshEvent(type: "mesh.event", sessionId: "task", eventId: id, projectId: "project",
                taskId: "task", sourceSessionId: "chat", eventType: "TASK_BLOCKED", createdAt: now + 1,
                payload: .init(reason: "Claude cloud did not start: Error: Unable to create cloud session"))
        }
        XCTAssertEqual(observe(snapshot(events: [blocked("new")])),
                       .failed("Claude cloud did not start: Error: Unable to create cloud session"))
        XCTAssertEqual(observe(snapshot(events: [blocked("old")])), .waiting, "an earlier refusal is not this one")

        var lookups = 0
        let started = await CloudHandoffOutcome.wait(lookup: {
            lookups += 1
            return lookups < 3 ? .waiting : .started(run)
        }, observing: { true }, pause: {})
        XCTAssertEqual(started, .started(run))
        let closed = await CloudHandoffOutcome.wait(lookup: { .waiting }, observing: { false }, pause: {})
        XCTAssertNil(closed)
        let unanswered = await CloudHandoffOutcome.wait(lookup: { .waiting }, observing: { true }, attempts: 2, pause: {})
        XCTAssertEqual(unanswered, .waiting)
    }

    func testAStartedRunIsShownAsALinkWithoutInventedProgress() {
        XCTAssertEqual(TaskHandoffCloudTarget.readiness(push: false).warning, true)
        XCTAssertEqual(TaskHandoffCloudTarget.readiness(push: true).warning, false)
        XCTAssertEqual(TaskRouteView.timingLine(cloudRun(startedAt: now), now: now + 3_600_000).contains("last active"), false)
        RenderProbe.render(CloudRunStartedNote(run: cloudRun(startedAt: now)), height: 120)
        RenderProbe.render(CloudRunLink(run: cloudRun(startedAt: now, url: nil)), height: 120)
    }
}
