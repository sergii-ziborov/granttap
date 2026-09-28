import XCTest
@testable import GrantTap

@MainActor
final class ProjectAuxiliaryContractTests: XCTestCase {
    func testSnapshotRetainsExecutionSkillsModelsAndEnvironmentAcrossRooms() throws {
        var reported = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        reported.skills = [.init(name: "review", state: "installed")]
        reported.mcpServers = [.init(
            name: "sourcekit-lsp", title: "SourceKit LSP", provider: "codex",
            endpointId: "vm", configuredEnabled: true, allowed: true,
            configDigest: String(repeating: "a", count: 64),
            sessionIds: ["session"]
        )]
        reported.capabilityRequests = [.init(
            projectId: "project", kind: .skill, name: "release",
            source: "owner/repo", version: "1.0.0", requestedAt: 1
        )]
        reported.execution = .init(mode: "pinned", targetEndpointId: "vm", revision: 1,
                                   hostGrantStatus: "applied")
        reported.restrictions = .init(projectId: "project", revision: 1, scope: "project",
                                      rules: [.init(ruleId: "lines", kind: "max_file_lines", limit: 300)])
        reported.environment = .init(projectId: "project", revision: 1, variables: [
            .init(key: "REGION", value: "west", secret: false),
        ])
        reported.modelCatalog = [.init(endpointId: "vm", observedAt: 1, models: [
            .init(modelId: "shared", provider: "codex", endpointId: "vm",
                  source: "advertised", observedAt: 1),
        ])]
        reported.backbone = .init(
            projectId: "project",
            nodes: [
                .init(kind: "service", identity: "api", displayName: "API"),
                .init(kind: "database", identity: "db", displayName: "Database"),
            ],
            relations: [.init(source: "api", target: "db", relation: "reads", evidenceCount: 2)],
            pendingCandidateCount: 0
        )
        let data = try JSONEncoder().encode(reported)
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(data))
        let decoded = try JSONDecoder().decode(ProjectMeshSnapshot.self, from: data)
        XCTAssertEqual(decoded.execution?.targetEndpointId, "vm")
        XCTAssertEqual(decoded.skills?.first?.name, "review")
        XCTAssertEqual(decoded.mcpServers?.first?.name, "sourcekit-lsp")
        XCTAssertEqual(decoded.mcpServers?.first?.configDigest, String(repeating: "a", count: 64))
        var malformed = reported
        malformed.mcpServers = [.init(
            name: "sourcekit-lsp", provider: "codex", endpointId: "vm",
            configuredEnabled: true, allowed: true, configDigest: "short", sessionIds: []
        )]
        XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(malformed)))
        XCTAssertEqual(decoded.capabilityRequests?.first?.name, "release")
        XCTAssertEqual(decoded.modelCatalog?.first?.models.first?.modelId, "shared")
        let graph = ProjectGraphModel.make(from: decoded)
        XCTAssertTrue(graph.nodes.flatMap(\.layers).contains { $0.label == "Database" })
        XCTAssertTrue(graph.nodes.flatMap(\.layers).contains { $0.kind == .mcp })
        let statistics = ProjectMeshStatistics.make(decoded)
        XCTAssertEqual(statistics.mcpServers, 1)
        XCTAssertEqual(statistics.graphRelations, 1)

        var later = reported
        later.execution = nil
        later.skills = nil
        later.mcpServers = nil
        later.capabilityRequests = nil
        later.modelCatalog = nil
        let merged = ProjectMeshLogic.merged(current: reported, incoming: later, nowMs: 2)
        XCTAssertEqual(merged.execution?.targetEndpointId, "vm")
        XCTAssertEqual(merged.skills?.first?.name, "review")
        XCTAssertEqual(merged.mcpServers?.first?.name, "sourcekit-lsp")
        XCTAssertEqual(merged.capabilityRequests?.first?.name, "release")
        XCTAssertEqual(merged.modelCatalog?.first?.endpointId, "vm")
    }

    func testPublisherReplacesOnlyItsOwnCapabilityInventory() {
        var first = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        first.publisherEndpointId = "mac-a"
        first.skills = [
            .init(name: "review", endpointId: "mac-a", digest: String(repeating: "a", count: 64)),
            .init(name: "qa", endpointId: "mac-b", digest: String(repeating: "b", count: 64)),
        ]
        first.mcpServers = [
            .init(name: "github", provider: "codex", endpointId: "mac-a",
                  configuredEnabled: true, allowed: true, version: "1", sessionIds: []),
            .init(name: "docs", provider: "claude", endpointId: "mac-b",
                  configuredEnabled: true, allowed: true, sessionIds: []),
        ]
        var next = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: first.project, tasks: [], executions: [], claims: [],
            dependencies: [], events: [], generatedAt: 2
        )
        next.publisherEndpointId = "mac-a"
        next.skills = []
        next.mcpServers = [
            .init(name: "github", provider: "codex", endpointId: "mac-a",
                  configuredEnabled: true, allowed: true, version: "2", sessionIds: [])
        ]
        let merged = ProjectMeshLogic.merged(current: first, incoming: next, nowMs: 2)
        XCTAssertEqual(merged.skills?.map(\.name), ["qa"])
        XCTAssertEqual(merged.mcpServers?.map(\.name), ["github", "docs"])
        XCTAssertEqual(merged.mcpServers?.first { $0.name == "github" }?.version, "2")
    }

    func testTwoPublishersRetainSeparateInventoryWithoutClaimingOnePublisher() {
        var first = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        first.publisherEndpointId = "mac-a"
        first.skills = [.init(name: "review", endpointId: "mac-a", state: "discovered")]
        var second = first
        second.publisherEndpointId = "mac-b"
        second.skills = [.init(name: "review", endpointId: "mac-b", state: "discovered")]
        let merged = ProjectMeshLogic.merged(current: first, incoming: second, nowMs: 2)
        XCTAssertNil(merged.publisherEndpointId)
        XCTAssertEqual(Set((merged.skills ?? []).compactMap(\.endpointId)), ["mac-a", "mac-b"])
    }

    func testGovernanceAcceptsAndPreservesAuxiliaryPolicy() throws {
        var status = ProjectGovernanceSyncFixtures.policyStatus(
            endpoint: "mac", provider: "claude", status: .enforced
        )
        status.policy.execution = .init(mode: "pinned", targetEndpointId: "mac", revision: 3)
        status.policy.restrictions = .init(projectId: "project", revision: 3, scope: "project",
                                           rules: [.init(ruleId: "lines", kind: "max_file_lines", limit: 300)])
        status.policy.environment = .init(projectId: "project", revision: 3, variables: [
            .init(key: "REGION", value: "west", secret: false),
        ])
        XCTAssertTrue(ProjectGovernanceWireValidator.validStatus(try JSONEncoder().encode(status)))
        let updated = ProjectGovernanceLogic.updatedPolicy(
            current: status.policy, projectId: "project", enforcement: .strict,
            defaults: [:], createdBy: "phone"
        )
        XCTAssertEqual(updated.execution?.targetEndpointId, "mac")
        XCTAssertEqual(updated.restrictions?.rules.first?.limit, 300)
        XCTAssertEqual(updated.environment?.variables.first?.key, "REGION")
    }

    func testProjectHostSelectionRejectsUnknownEndpointAndKeepsAnExplicitRoute() throws {
        ProjectPolicyOutboxStore.clear()
        defer { ProjectPolicyOutboxStore.clear() }
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var project = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "route-project", projectId: "route-project",
            project: .init(projectId: "route-project", name: "Route",
                           canonicalRepositoryId: "repository", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        project.bindings = [.init(
            bindingId: "binding", projectId: "route-project", endpointId: "allowed-host",
            repositoryId: "repository", displayName: "Allowed host", available: true
        )]
        model.meshSnapshots[project.projectId] = project
        model.meshProjectSourceRooms[project.projectId] = ["room"]
        model.projectGovernance[project.projectId] = .init(
            projectId: project.projectId, revision: 0, enforcement: .bestAvailable,
            rules: [], coverage: [], updatedAt: 1
        )

        XCTAssertFalse(model.setProjectExecutionHost(projectId: project.projectId,
                                                     endpointId: "unknown-host"))
        XCTAssertTrue(model.projectPolicyOutbox.isEmpty)
        XCTAssertTrue(model.setProjectExecutionHost(projectId: project.projectId,
                                                    endpointId: "allowed-host"))
        let request = try XCTUnwrap(model.projectPolicyOutbox.first?.request)
        XCTAssertEqual(request.policy.execution?.targetEndpointId, "allowed-host")
        XCTAssertEqual(request.policy.execution?.hostGrantStatus, "pending")
        XCTAssertEqual(request.policy.execution?.revision, 1)
        XCTAssertEqual(model.projectPolicyOutbox.count, 1)
    }
}
