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
            "\(ProjectManagePresentation.meshSummary(snapshot)) · \(ProjectRepoLensPresentation.graph(snapshot).rowDetail)"
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

    func testRestrictionAndEnvironmentSummariesFollowSnapshotThenPolicy() {
        var snapshot = emptySnapshot()
        XCTAssertEqual(
            ProjectRestrictionsPresentation.summary(snapshot, governance: nil),
            L("No restrictions")
        )
        XCTAssertEqual(
            ProjectEnvironmentPresentation.summary(snapshot, governance: nil),
            L("No variables")
        )
        snapshot.restrictions = ProjectRestrictionSet(
            projectId: "project", revision: 1, scope: .projectAndRepo,
            rules: [
                ProjectRestrictionRule(ruleId: "max-file-lines", kind: .maxFileLines, limit: 500)
            ]
        )
        snapshot.environment = ProjectEnvironment(
            projectId: "project", revision: 1, shareNonSecretsWithRepo: true,
            variables: [
                ProjectEnvVar(key: "PUBLIC_URL", value: "https://example.test", secret: false),
                ProjectEnvVar(key: "API_TOKEN", secret: true),
            ]
        )
        XCTAssertEqual(
            ProjectRestrictionsPresentation.summary(snapshot, governance: nil),
            "\(String(format: L("%d rule"), 1)) · \(L("Project and repository"))"
        )
        XCTAssertTrue(ProjectEnvironmentPresentation.summary(snapshot, governance: nil)
            .contains(L("shared with the repository")))
        XCTAssertTrue(ProjectEnvironmentPresentation.isValidKey("PUBLIC_URL"))
        XCTAssertFalse(ProjectEnvironmentPresentation.isValidKey("public-url"))
        let merged = ProjectEnvironmentLogic.mergingSecrets(
            current: ProjectEnvironment(
                projectId: "project", revision: 1,
                variables: [ProjectEnvVar(key: "API_TOKEN", value: "kept", secret: true)]
            ),
            incoming: snapshot.environment
        )
        XCTAssertEqual(merged?.variables.first { $0.key == "API_TOKEN" }?.value, "kept")
        _ = ProjectRestrictionsView(snapshot: snapshot, model: AppModel()).body
        _ = ProjectEnvironmentView(snapshot: snapshot, model: AppModel()).body
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
            "\(L("Waiting for host")) · r-host-1"
        )
    }

    func testRepoLensGraphShowsTheProjectAndItsStatedEdges() {
        var snapshot = emptySnapshot()
        let empty = ProjectRepoLensPresentation.graph(snapshot)
        XCTAssertEqual(empty.nodes.map(\.id), ["github.com/example/granttap"])
        XCTAssertTrue(empty.edges.isEmpty)
        XCTAssertEqual(empty.rowDetail, "1 repository")
        XCTAssertEqual(ProjectOverviewPresentation.newChatDetail(snapshot), "GrantTap")

        snapshot.bindings = [
            .init(bindingId: "b", projectId: "project", endpointId: "Mac",
                  repositoryId: "github.com/example/granttap", displayName: "granttap-mcp",
                  available: true),
            .init(bindingId: "site", projectId: "project", endpointId: "Mac",
                  repositoryId: "github.com/example/granttap-site", displayName: "granttap-site",
                  available: true),
        ]
        snapshot.peers = [
            ProjectIntegrationPeer(
                projectId: "project", repositoryId: "github.com/example/granttap",
                peer: "granttap-site", via: "api", relation: "calls", updatedAt: now
            )
        ]
        let graph = ProjectRepoLensPresentation.graph(snapshot)
        XCTAssertEqual(Set(graph.nodes.map(\.title)), ["granttap-mcp", "granttap-site"])
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges.first?.from, "github.com/example/granttap")
        XCTAssertEqual(graph.edges.first?.to, "github.com/example/granttap-site")
        XCTAssertTrue(graph.rowDetail.contains("2 repositories"))
        XCTAssertTrue(graph.rowDetail.contains("1 edge"))
    }

    func testAddedToolsAppearOnTheProjectCatalog() {
        let model = AppModel()
        let snapshot = emptySnapshot()
        let other = emptySnapshot(projectId: "other")
        model.globalMcpDisabled = ["github"]
        model.globalSkillsDisabled = ["release-check"]
        XCTAssertTrue(ProjectToolsSkillsPresentation.catalog(snapshot: snapshot).isEmpty)
        model.addProjectTool(projectId: snapshot.projectId, kind: .skill, name: "release-check")
        model.addProjectTool(projectId: snapshot.projectId, kind: .mcp, name: "github")
        let catalog = ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot, added: model.addedToolItems(for: snapshot.projectId)
        )
        XCTAssertEqual(catalog.skills.map(\.name), ["release-check"])
        XCTAssertEqual(catalog.servers.map(\.name), ["github"])
        XCTAssertEqual(catalog.items(kind: .skill, state: "requested").map(\.name), ["release-check"])
        XCTAssertEqual(catalog.items(kind: .mcp, state: "requested").map(\.name), ["github"])
        XCTAssertEqual(ProjectToolsSkillsPresentation.stateLabel("requested"), L("Requested"))
        XCTAssertEqual(model.addedToolItems(for: other.projectId), [])
        XCTAssertEqual(model.globalMcpDisabled, ["github"])
        XCTAssertEqual(model.globalSkillsDisabled, ["release-check"])
        ProjectGovernanceViewFixtures.render(ProjectToolsSkillsAddSheet(snapshot: snapshot, model: model))
        ProjectGovernanceViewFixtures.render(ProjectRepoLensGraphView(graph: .init(nodes: [], edges: [])))
    }

    func testHostModelsUseOnlyTheExactEndpointCatalog() {
        var snapshot = emptySnapshot()
        snapshot.modelCatalog = [
            EndpointModelCatalog(
                endpointId: "other-host", observedAt: now,
                models: [
                    AdvertisedModel(
                        modelId: "opus", provider: "claude", endpointId: "other-host",
                        source: "observed", observedAt: now
                    )
                ]
            ),
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
        XCTAssertEqual(
            ProjectExecutionPresentation.catalog(snapshot: snapshot, targetId: "mac-host")?
                .models.map(\.modelId),
            ["sonnet"]
        )
        XCTAssertNil(ProjectExecutionPresentation.catalog(snapshot: snapshot, targetId: "missing-host"))
    }

    func testProjectNewChatKeepsOnlyThisProjectsFolders() {
        var snapshot = emptySnapshot()
        snapshot.bindings = [
            .init(bindingId: "b", projectId: snapshot.projectId, endpointId: "Mac",
                  repositoryId: snapshot.project.canonicalRepositoryId, displayName: "granttap",
                  localPathHint: "/repo", available: true)
        ]
        XCTAssertEqual(
            ProjectWorkspacePresentation.folders(
                snapshot: snapshot, advertised: ["/repo", "/other"]
            ),
            ["/repo"]
        )
        XCTAssertEqual(
            ProjectWorkspacePresentation.folders(
                snapshot: snapshot, advertised: ["/other"]
            ),
            []
        )
    }

    private func emptySnapshot(projectId: String = "project") -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(
                projectId: projectId, name: "GrantTap", repositoryRoot: "/repo",
                canonicalRepositoryId: "github.com/example/granttap", createdAt: now
            ),
            tasks: [], executions: [], claims: [], dependencies: [], events: [],
            generatedAt: now
        )
    }
}
