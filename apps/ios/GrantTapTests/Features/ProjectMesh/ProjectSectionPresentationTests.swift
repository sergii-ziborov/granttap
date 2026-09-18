import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectSectionPresentationTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    func testToolsAndSkillsSummaryUsesProjectCatalogWhenSessionSkillsAreEmpty() {
        var snapshot = emptySnapshot()
        snapshot.skills = [
            SharedSkill(name: "release-check", version: "1.0", digest: String(repeating: "b", count: 64),
                        source: "repo", state: "installed"),
            SharedSkill(name: "docs", state: nil),
        ]
        var session = SessionInfo(
            sessionId: "chat", agent: "codex", title: "Release", state: "working",
            startedAt: now, lastActivityAt: now, tokensSession: 1, tokensLastTurn: 1
        )
        session.projectId = snapshot.projectId
        session.skills = []
        session.mcpServers = [
            McpServerInfo(name: "github", configuredEnabled: true, allowed: true, version: "2.1"),
            McpServerInfo(name: "figma", configuredEnabled: false, allowed: true),
        ]
        let used = CapabilityUsageEvent(
            id: "use-1", sourceId: "src", agent: "codex", kind: .mcp, name: "github",
            sessionId: "owner", createdAt: now
        )
        snapshot.executions = [
            ExecutionSessionLink(
                taskId: "task", sessionId: "owner", provider: "codex", computerId: "Mac",
                workspace: "/repo", startedAt: now
            )
        ]
        let catalog = ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot, sessions: [session], usage: [used]
        )
        XCTAssertEqual(catalog.skills.map(\.name), ["docs", "release-check"])
        XCTAssertEqual(catalog.skills.first { $0.name == "docs" }?.state, "unknown")
        XCTAssertEqual(catalog.skills.first { $0.name == "release-check" }?.state, "installed")
        XCTAssertTrue(catalog.skills.first { $0.name == "release-check" }?.detail.contains("\(L("Desired")) 1.0") == true)
        XCTAssertEqual(catalog.servers.map(\.name), ["figma", "github"])
        XCTAssertEqual(catalog.items(kind: .mcp, state: "installed").map(\.name), ["github"])
        XCTAssertEqual(catalog.items(kind: .mcp, state: "available").map(\.name), ["figma"])
        XCTAssertEqual(ProjectToolsSkillsPresentation.usageLabel(name: "github", usedNames: catalog.usedNames), L("Used"))
        XCTAssertEqual(ProjectToolsSkillsPresentation.usageLabel(name: "figma", usedNames: catalog.usedNames), L("Unknown"))
        XCTAssertFalse(catalog.rowDetail.localizedCaseInsensitiveContains("unused"))
        XCTAssertTrue(catalog.rowDetail.contains("2 skills"))
        XCTAssertTrue(catalog.rowDetail.contains("2 MCP"))
        XCTAssertEqual(session.skills ?? [], [], "session skills stay empty; the Project list is not injected")
    }

    func testToolsAndSkillsMissingUsageIsUnknownNeverProvenUnused() {
        var snapshot = emptySnapshot()
        snapshot.skills = [SharedSkill(name: "ios-qa", state: "available")]
        snapshot.incomplete = true
        let catalog = ProjectToolsSkillsPresentation.catalog(snapshot: snapshot, sessions: [], usage: [])
        XCTAssertEqual(catalog.items(kind: .skill, state: "available").map(\.name), ["ios-qa"])
        XCTAssertEqual(
            ProjectToolsSkillsPresentation.usageLabel(name: "ios-qa", usedNames: catalog.usedNames),
            L("Unknown")
        )
        XCTAssertTrue(catalog.incomplete)
        XCTAssertTrue(catalog.rowDetail.contains(L("incomplete")))
        XCTAssertFalse(catalog.rowDetail.localizedCaseInsensitiveContains("unused"))
        XCTAssertFalse(catalog.rowDetail.localizedCaseInsensitiveContains("proven"))
    }

    func testKnowledgeEmptyVersusPopulatedSummaries() {
        let empty = ProjectKnowledgePresentation.summary(snapshot: emptySnapshot())
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.rowDetail, L("Nothing recorded yet"))
        XCTAssertEqual(empty.source, L("Project snapshot"))

        var snapshot = emptySnapshot()
        let capsule = TaskCapsule(
            taskId: "task", goal: "Ship the audit", currentStatus: "Reviewing",
            sourceProvider: "claude", sourceComputer: "Mac", targetProvider: "codex",
            targetComputer: "PC", repository: "github.com/example/granttap",
            baseSha: String(repeating: "a", count: 40), filesChanged: [],
            dependencies: [], resourceClaims: [], remainingWork: ["Run Watch tests"],
            importantDecisions: ["Keep task identity"], createdAt: now
        )
        snapshot.tasks = [
            ProjectMeshTask(
                taskId: "task", projectId: snapshot.projectId, title: "Audit",
                goal: "Ship the audit", state: "working", ownerSessionId: "owner",
                createdAt: now, updatedAt: now
            )
        ]
        snapshot.events = [
            ProjectMeshEvent(
                type: "mesh.event", sessionId: "task", eventId: "handoff",
                projectId: snapshot.projectId, taskId: "task",
                sourceSessionId: "owner", eventType: "HANDOFF_REQUEST",
                createdAt: now, payload: .init(capsule: capsule)
            ),
            ProjectMeshEvent(
                type: "mesh.event", sessionId: "task", eventId: "blocked",
                projectId: snapshot.projectId, taskId: "task",
                sourceSessionId: "owner", eventType: "TASK_BLOCKED",
                createdAt: now + 1, payload: .init(summary: "Waiting on pairing", needsUser: true)
            )
        ]
        let invocation = ProjectInvocationRecord(
            room: "room", sequence: 1,
            event: ProjectInvocationEvent(
                event_id: "ev", invocation_id: "inv", project_id: snapshot.projectId,
                task_id: "task", execution_id: "ex", provider: "claude",
                native_call_id: "n", session_id: "owner", tool_name: "Edit",
                phase: "reported_success", source: "transcript", occurred_at: now + 2,
                repository_id: nil, worktree: nil, resource: nil, revision: nil,
                content_hash: nil, capability_artifact_hash: nil, policy_revision: nil,
                policy_rule_id: nil
            )
        )
        let populated = ProjectKnowledgePresentation.summary(
            snapshot: snapshot, invocations: [invocation]
        )
        XCTAssertFalse(populated.isEmpty)
        XCTAssertEqual(populated.decisions, ["Keep task identity"])
        XCTAssertTrue(populated.attempts.contains { $0.contains("Edit") })
        XCTAssertTrue(populated.attempts.contains { $0.contains("Waiting on pairing") })
        XCTAssertTrue(populated.agentContext.contains("Ship the audit"))
        XCTAssertTrue(populated.agentContext.contains("Run Watch tests"))
        XCTAssertEqual(populated.source, L("Agent transcript"))
        XCTAssertTrue(populated.rowDetail.contains("1 decision"))
        XCTAssertTrue(populated.rowDetail.contains("2 attempts"))
    }

    func testHealthAndWorkingSummariesStayCompact() {
        var snapshot = emptySnapshot()
        XCTAssertEqual(ProjectManagePresentation.workingSummary(snapshot), "0 tasks · 0 executors")
        XCTAssertEqual(
            ProjectManagePresentation.healthSummary(snapshot),
            "\(ProjectManagePresentation.meshSummary(snapshot)) · \(L("Usage not yet observed"))"
        )
        snapshot.tasks = [
            ProjectMeshTask(
                taskId: "task", projectId: snapshot.projectId, title: "Audit",
                goal: "g", state: "working", createdAt: now, updatedAt: now
            )
        ]
        snapshot.executions = [
            ExecutionSessionLink(
                taskId: "task", sessionId: "owner", provider: "codex", computerId: "Mac",
                workspace: "/repo", startedAt: now
            )
        ]
        XCTAssertEqual(ProjectManagePresentation.workingSummary(snapshot), "1 task · 1 executor")
        let usage = CapabilityUsageEvent(
            id: "u", sourceId: "s", kind: .cli, name: "rg", sessionId: "owner", createdAt: now
        )
        XCTAssertTrue(ProjectManagePresentation.healthSummary(snapshot, usageEvents: [usage]).contains("1 call"))
        XCTAssertEqual(ProjectOverviewPresentation.recipientCount(snapshot), 1)
        XCTAssertEqual(ProjectOverviewPresentation.writeDetail(snapshot), "1 recipient")
        XCTAssertEqual(
            TaskContextPresentation.deliveryLabel(offered: true, issued: false, confirmed: false),
            L("Offered to agent")
        )
    }

    func testKnowledgeAndToolsScreensRenderEmptyAndPopulated() {
        let model = AppModel()
        let empty = emptySnapshot()
        ProjectGovernanceViewFixtures.render(ProjectKnowledgeView(snapshot: empty, model: model))
        ProjectGovernanceViewFixtures.render(ProjectToolsSkillsView(snapshot: empty, model: model))
        ProjectGovernanceViewFixtures.render(ProjectWriteToAgentsSheet(snapshot: empty, model: model))

        var populated = empty
        populated.skills = [SharedSkill(name: "release-check", version: "1.0", state: "installed")]
        populated.incomplete = true
        populated.tasks = [
            ProjectMeshTask(
                taskId: "task", projectId: populated.projectId, title: "Audit",
                goal: "Ship", state: "working", createdAt: now, updatedAt: now
            )
        ]
        populated.events = [
            ProjectMeshEvent(
                type: "mesh.event", sessionId: "task", eventId: "handoff",
                projectId: populated.projectId, taskId: "task",
                sourceSessionId: "owner", eventType: "HANDOFF_REQUEST",
                createdAt: now,
                payload: .init(capsule: TaskCapsule(
                    taskId: "task", goal: "Ship", currentStatus: "Working",
                    sourceProvider: "claude", sourceComputer: "Mac", targetProvider: "codex",
                    targetComputer: "PC", repository: "github.com/example/granttap",
                    baseSha: String(repeating: "a", count: 40), filesChanged: [],
                    dependencies: [], resourceClaims: [], remainingWork: ["Test"],
                    importantDecisions: ["Keep identity"], createdAt: now
                ))
            )
        ]
        model.invocationHistoryByTask[AppModel.invocationTaskKey(populated.projectId, "task")] = [
            ProjectInvocationRecord(
                room: "room", sequence: 1,
                event: ProjectInvocationEvent(
                    event_id: "ev", invocation_id: "inv", project_id: populated.projectId,
                    task_id: "task", execution_id: "ex", provider: "claude",
                    native_call_id: "n", session_id: "owner", tool_name: "Edit",
                    phase: "requested", source: "transcript", occurred_at: now,
                    repository_id: nil, worktree: nil, resource: nil, revision: nil,
                    content_hash: nil, capability_artifact_hash: nil, policy_revision: nil,
                    policy_rule_id: nil
                )
            )
        ]
        ProjectGovernanceViewFixtures.render(ProjectKnowledgeView(snapshot: populated, model: model))
        ProjectGovernanceViewFixtures.render(ProjectToolsSkillsView(snapshot: populated, model: model))
        ProjectGovernanceViewFixtures.render(
            List { ProjectDestinationRows(snapshot: populated, model: model) }
        )
        ProjectGovernanceViewFixtures.render(
            ProjectMeshView(snapshot: populated, model: model)
        )
    }

    func testPinnedModeLocksTheHostAndKeepsAliasOffTheRoute() {
        var snapshot = emptySnapshot()
        snapshot.execution = ProjectExecutionPolicy(
            mode: .pinned, targetEndpointId: "mac-host", revision: 3,
            hostGrantStatus: .applied
        )
        snapshot.modelCatalog = [
            EndpointModelCatalog(
                endpointId: "mac-host", observedAt: now,
                models: [
                    AdvertisedModel(
                        modelId: "sonnet", provider: "claude", endpointId: "mac-host",
                        source: "observed", observedAt: now
                    )
                ]
            )
        ]
        XCTAssertEqual(snapshot.execution?.targetEndpointId, "mac-host")
        XCTAssertEqual(snapshot.modelCatalog?.first?.models.map(\.modelId), ["sonnet"])
        XCTAssertNotEqual(snapshot.project.name, snapshot.execution?.targetEndpointId)
    }

    func testExecutionSummaryDistinguishesPinnedPendingFromDistributed() {
        var snapshot = emptySnapshot()
        XCTAssertEqual(
            ProjectManagePresentation.executionSummary(snapshot, governance: nil),
            L("Distributed")
        )
        snapshot.execution = ProjectExecutionPolicy(
            mode: .pinned, targetEndpointId: "computer-host-1", revision: 2,
            hostGrantStatus: .pending
        )
        XCTAssertEqual(
            ProjectManagePresentation.executionSummary(snapshot, governance: nil),
            "\(L("Waiting for host")) · ost-1"
        )
    }

    private func emptySnapshot() -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(
                projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                canonicalRepositoryId: "github.com/example/granttap", createdAt: now
            ),
            tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: now
        )
    }
}
