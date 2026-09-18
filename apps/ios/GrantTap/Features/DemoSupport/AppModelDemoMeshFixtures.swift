import Foundation

enum AppModelDemoMeshFixtures {
    static let projectId = "granttap-project-demo"
    static let releaseTaskId = "granttap-release-task-demo"
    static let pairingTaskId = "granttap-pairing-task-demo"
    static let previousClaudeSessionId = "granttap-claude-handoff-demo"

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
                    endpointId: "MacBook", repositoryId: "granttap",
                    displayName: "GrantTap iPhone", available: true,
                    revision: String(repeating: "b", count: 40)
                ),
                .init(
                    bindingId: "demo-runtime-binding", projectId: projectId,
                    endpointId: "Workstation", repositoryId: "granttap-mcp",
                    displayName: "GrantTap MCP", available: true,
                    revision: String(repeating: "d", count: 40)
                ),
            ],
            skills: [
                SharedSkill(
                    name: "release-check",
                    description: "Run the repository release checklist",
                    version: "1.0",
                    digest: String(repeating: "a", count: 64),
                    source: "repo", state: "installed"
                ),
                SharedSkill(
                    name: "ios-qa",
                    description: "Verify the iPhone and Apple Watch apps",
                    version: "1.1", source: "repo", state: "available"
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
