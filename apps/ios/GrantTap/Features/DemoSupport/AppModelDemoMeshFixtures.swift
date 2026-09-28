import Foundation

enum AppModelDemoMeshFixtures {
    static let projectId = "granttap-project-demo"
    static let linkedProjectId = "granttap-runtime-demo"
    static let releaseTaskId = "granttap-release-task-demo"
    static let pairingTaskId = "granttap-pairing-task-demo"
    static let previousClaudeSessionId = "granttap-claude-handoff-demo"

    #if DEBUG
    static func linkedSnapshot(at now: Double) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: linkedProjectId, projectId: linkedProjectId,
            project: .init(projectId: linkedProjectId, name: "GrantTap MCP",
                           repositoryRoot: "/Users/reviewer/granttap-mcp",
                           canonicalRepositoryId: "github.com/sergii-ziborov/granttap-mcp",
                           createdAt: now - 3_600_000),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: now
        )
    }
    #endif

    static func architectureGraph() -> ProjectRepositoryGraph {
        let nodes: [ProjectRepositoryGraph.Node] = [
            .init(id: "app", kind: "workspace", label: "GrantTap"),
            .init(id: "ios", kind: "package", label: "iPhone App"),
            .init(id: "watch", kind: "package", label: "Watch"),
            .init(id: "engine", kind: "component", label: "Engine"),
            .init(id: "relay", kind: "component", label: "Relay"),
        ]
        let relations: [ProjectRepositoryGraph.Relation] = [
            .init(source: "app", target: "ios", relation: "owns", evidenceCount: 1),
            .init(source: "app", target: "watch", relation: "owns", evidenceCount: 1),
            .init(source: "ios", target: "engine", relation: "uses", evidenceCount: 2),
            .init(source: "watch", target: "relay", relation: "uses", evidenceCount: 1),
        ]
        var report = ProjectRepositoryGraph(
            projectId: projectId, repositoryId: "github.com/sergii-ziborov/granttap",
            revision: "demo-revision", weavatrixVersion: "2.17.4", analysisStatus: "COMPLETE",
            nodes: nodes, relations: relations, totalNodes: nodes.count,
            totalRelations: relations.count, truncated: false
        )
        let files: [ProjectCodeMap.File] = [
            .init(path: "apps/ios/GrantTap/ContentView.swift", language: "swift", lineCount: 420,
                  symbols: [.init(id: "content", label: "ContentView", kind: "struct",
                                  startLine: 12, lineCount: 160)]),
            .init(path: "apps/ios/GrantTap/ProjectView.swift", language: "swift", lineCount: 275,
                  symbols: [.init(id: "project", label: "ProjectView", kind: "struct",
                                  startLine: 9, lineCount: 140)]),
            .init(path: "apps/ios/GrantTap/HealthView.swift", language: "swift", lineCount: 180,
                  symbols: [.init(id: "health", label: "HealthView", kind: "struct",
                                  startLine: 7, lineCount: 90)]),
            .init(path: "apps/watch/WatchHome.swift", language: "swift", lineCount: 155,
                  symbols: [.init(id: "watch-home", label: "WatchHome", kind: "struct",
                                  startLine: 5, lineCount: 90)]),
            .init(path: "runtime/engine/project.rs", language: "rust", lineCount: 380,
                  symbols: [.init(id: "project-runtime", label: "ProjectRuntime", kind: "struct",
                                  startLine: 20, lineCount: 130)]),
            .init(path: "runtime/engine/graph.rs", language: "rust", lineCount: 315,
                  symbols: [.init(id: "graph-runtime", label: "analyze", kind: "function",
                                  startLine: 14, lineCount: 120)]),
            .init(path: "runtime/bridge/mesh.ts", language: "typescript", lineCount: 240,
                  symbols: [.init(id: "mesh-runtime", label: "publishSnapshot", kind: "function",
                                  startLine: 17, lineCount: 85)]),
            .init(path: "runtime/bridge/policy.ts", language: "typescript", lineCount: 190,
                  symbols: [.init(id: "policy-runtime", label: "effectiveAction", kind: "function",
                                  startLine: 11, lineCount: 65)]),
            .init(path: "README.md", language: "markdown", lineCount: 96, symbols: []),
        ]
        report.codeMap = ProjectCodeMap(files: files,
            externals: [.init(id: "ext:relay", label: "Relay service", kind: "service")], roads: [
            .init(source: files[0].path, target: files[6].path, relation: "calls"),
            .init(source: files[1].path, target: files[4].path, relation: "calls"),
            .init(source: files[2].path, target: files[5].path, relation: "calls"),
            .init(source: files[4].path, target: files[5].path, relation: "imports"),
            .init(source: files[6].path, target: files[7].path, relation: "imports"),
            .init(source: files[2].path, target: "ext:relay", relation: "consumes"),
        ], totalFiles: files.count, totalExternals: 1, truncated: false)
        return report
    }

    #if DEBUG
    static func largeArchitectureGraph() -> ProjectRepositoryGraph {
        var report = architectureGraph()
        report.analysisStatus = "INCOMPLETE"
        let files = (0..<650).map { index in
            ProjectCodeMap.File(
                path: "apps/ios/GrantTap/Features/Area\(index / 25)/Source\(index).swift",
                language: "swift", lineCount: 20 + index, symbols: []
            )
        }
        let roads = (0..<75).map { index in
            ProjectCodeMap.Road(source: files[index].path, target: files[index + 1].path,
                                relation: "imports")
        }
        report.codeMap = ProjectCodeMap(files: files, roads: roads, totalFiles: 653,
                                        truncated: true)
        return report
    }
    #endif

    static func snapshot(at now: Double) -> ProjectMeshSnapshot {
        let capsule = TaskCapsule(
            taskId: releaseTaskId, goal: L("Complete the GrantTap release audit"),
            currentStatus: L("Implementation review complete"), sourceProvider: "claude",
            sourceComputer: "MacBook", targetProvider: "codex", targetComputer: "Workstation",
            repository: "github.com/sergii-ziborov/granttap", baseSha: String(repeating: "a", count: 40),
            branch: "claude/release-review", latestCommit: String(repeating: "b", count: 40),
            dirtyDiffHash: nil, filesChanged: ["apps/ios/GrantTap"], testsStatus: "Unit tests pass",
            dependencies: [pairingTaskId], resourceClaims: ["apps/ios/GrantTapTests/**"],
            remainingWork: ["Run the iPhone and Watch regression suites"],
            importantDecisions: ["Keep task identity across the handoff"], createdAt: now - 420_000
        )
        let capsuleHash = ProjectMeshReceiptValidator.capsuleHash(capsule)
            ?? String(repeating: "c", count: 64)
        let receipt = ProjectHandoffReceipt(
            sourceSessionId: previousClaudeSessionId,
            targetSessionId: AppModelDemoFixtures.codexSessionId,
            taskId: releaseTaskId, capsuleHash: capsuleHash,
            acceptedAt: now - 360_000
        )
        return ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(
                projectId: projectId, name: "GrantTap", repositoryRoot: "/Users/reviewer/granttap",
                canonicalRepositoryId: "github.com/sergii-ziborov/granttap",
                baseRemote: "git@github.com:sergii-ziborov/granttap.git", createdAt: now - 3_600_000
            ),
            bindings: [
                .init(
                    bindingId: "demo-ios-binding", projectId: projectId,
                    endpointId: "MacBook",
                    repositoryId: "github.com/sergii-ziborov/granttap",
                    displayName: "GrantTap iPhone", available: true,
                    revision: String(repeating: "b", count: 40)
                ),
                .init(
                    bindingId: "demo-runtime-binding", projectId: projectId,
                    endpointId: "Workstation",
                    repositoryId: "github.com/sergii-ziborov/granttap-mcp",
                    displayName: "GrantTap MCP", available: true,
                    revision: String(repeating: "d", count: 40)
                ),
            ],
            tasks: [
                .init(taskId: releaseTaskId, projectId: projectId, title: "GrantTap release audit",
                      goal: capsule.goal, state: "working",
                      ownerSessionId: AppModelDemoFixtures.codexSessionId,
                      createdAt: now - 900_000, updatedAt: now),
                .init(taskId: pairingTaskId, projectId: projectId, title: "Pairing API review",
                      goal: L("Finalize the pairing API"), state: "blocked",
                      ownerSessionId: AppModelDemoFixtures.claudeSessionId,
                      createdAt: now - 1_200_000, updatedAt: now - 120_000),
            ],
            executions: [
                .init(taskId: releaseTaskId, sessionId: previousClaudeSessionId,
                      provider: "claude", computerId: "MacBook", workspace: "/Users/reviewer/granttap",
                      branch: "claude/release-review", worktree: "/Users/reviewer/granttap-review",
                      startedAt: now - 900_000, endedAt: receipt.acceptedAt),
                .init(taskId: releaseTaskId, sessionId: AppModelDemoFixtures.codexSessionId,
                      provider: "codex", computerId: "Workstation", workspace: "/Users/reviewer/granttap",
                      branch: "release/1.0", worktree: "/Users/reviewer/granttap-release",
                      startedAt: receipt.acceptedAt, endedAt: nil),
                .init(taskId: pairingTaskId, sessionId: AppModelDemoFixtures.claudeSessionId,
                      provider: "claude", computerId: "MacBook", workspace: "/Users/reviewer/granttap",
                      branch: "claude/pairing-api", worktree: "/Users/reviewer/granttap-pairing",
                      startedAt: now - 1_200_000, endedAt: nil),
            ],
            claims: [.init(
                claimId: "demo-pairing-claim", projectId: projectId, taskId: pairingTaskId,
                ownerSessionId: AppModelDemoFixtures.claudeSessionId, resource: "packages/pairing/**",
                mode: "claim", createdAt: now - 300_000, expiresAt: now + 300_000
            )],
            dependencies: [.init(
                taskId: releaseTaskId, dependsOnTaskId: pairingTaskId,
                summary: L("Waiting for the pairing API"), createdAt: now - 240_000
            )],
            events: [
                .init(type: "mesh.event", sessionId: releaseTaskId, eventId: "demo-handoff-request",
                      projectId: projectId, taskId: releaseTaskId,
                      sourceSessionId: previousClaudeSessionId,
                      targetSessionId: AppModelDemoFixtures.codexSessionId,
                      eventType: "HANDOFF_REQUEST", createdAt: capsule.createdAt,
                      expiresAt: nil, payload: .init(capsule: capsule)),
                .init(type: "mesh.event", sessionId: releaseTaskId, eventId: "demo-handoff-accepted",
                      projectId: projectId, taskId: releaseTaskId,
                      sourceSessionId: AppModelDemoFixtures.codexSessionId,
                      targetSessionId: previousClaudeSessionId,
                      eventType: "HANDOFF_ACCEPTED", createdAt: receipt.acceptedAt,
                      expiresAt: nil, payload: .init(receipt: receipt)),
            ],
            generatedAt: now
        )
    }

    static func governance(at now: Double) -> ProjectGovernanceProjection {
        let policy = ProjectPolicy(
            projectId: projectId, revision: 6, enforcement: .bestAvailable,
            rules: [
                ProjectPolicyRule(
                    ruleId: "demo-deploy-ask", projectId: projectId,
                    selector: ProjectPolicySelector(
                        kind: .deploy, displayName: "Production deploy"
                    ), effect: .ask,
                    conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                    revision: 6, createdBy: "demo"
                ),
                ProjectPolicyRule(
                    ruleId: "demo-unknown-mcp-deny", projectId: projectId,
                    selector: ProjectPolicySelector(
                        kind: .mcp, displayName: "Unknown MCP",
                        fingerprint: ProjectFingerprintPredicate(
                            match: .confidence, value: .unknown
                        )
                    ), effect: .deny,
                    conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                    revision: 6, createdBy: "demo"
                ),
            ]
        )
        return ProjectGovernanceProjection(
            projectId: projectId, revision: 6, enforcement: .bestAvailable,
            rules: [
                .init(
                    ruleId: "demo-deploy-ask", effect: .ask,
                    capabilityKind: "deploy", displayName: "Production deploy"
                ),
                .init(
                    ruleId: "demo-unknown-mcp-deny", effect: .deny,
                    capabilityKind: "mcp", displayName: "Unknown MCP",
                    fingerprintConfidence: "unknown"
                ),
            ],
            coverage: [
                .init(
                    endpointId: "MacBook", provider: "claude", capability: "Shell",
                    status: .enforced, policyRevision: 6
                ),
                .init(
                    endpointId: "Workstation", provider: "codex", capability: "MCP",
                    status: .enforced, policyRevision: 6
                ),
                .init(
                    endpointId: "Workstation", provider: "grok", capability: "Shell",
                    status: .observed, policyRevision: 6
                ),
            ],
            updatedAt: now, requiredCapabilities: [], strictReady: true, policy: policy
        )
    }

    static func previousActivity(at now: Double) -> SessionActivity {
        SessionActivity(
            sessionId: previousClaudeSessionId, agent: "claude", state: "idle",
            entries: [.init(
                id: "demo-mesh-claude-progress", kind: "message",
                text: L("Implementation review complete. Handing regression coverage to Codex."),
                createdAt: now - 390_000
            )], generatedAt: now
        )
    }
}
