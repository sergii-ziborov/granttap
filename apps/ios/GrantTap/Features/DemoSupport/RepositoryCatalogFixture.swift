import Foundation

/// Simulator-only repository navigation evidence; never changes real Mesh data.
enum RepositoryCatalogFixture {
    @MainActor static func apply(to model: AppModel, at now: Double) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_REPOSITORIES"] == "1",
              var mesh = model.meshSnapshots[AppModelDemoMeshFixtures.projectId] else { return }
        let runtime = "github.com/sergii-ziborov/granttap-mcp"
        for index in mesh.executions.indices {
            mesh.executions[index].repositoryId = mesh.executions[index].taskId == AppModelDemoMeshFixtures.pairingTaskId
                ? runtime : mesh.project.canonicalRepositoryId
        }
        var linked = AppModelDemoMeshFixtures.linkedSnapshot(at: now)
        linked.tasks = [.init(taskId: "other-scope-chat", projectId: linked.projectId,
            title: "Pairing API review", goal: "", state: "working", ownerSessionId: "other-native",
            createdAt: now - 500, updatedAt: now)]
        linked.executions = [.init(taskId: "other-scope-chat", sessionId: "other-native",
            provider: "codex", computerId: "Workstation", workspace: "/fixture",
            repositoryId: runtime, branch: "fix/pairing", startedAt: now - 500)]
        linked.repositoryDetails = [.init(projectId: linked.projectId, repositoryId: runtime,
            canonicalRepositoryId: runtime, endpointId: "Workstation", status: "ready",
            branch: "fix/pairing", revision: String(repeating: "a", count: 40), dirty: false, commitCount: 17,
            commits: [.init(sha: String(repeating: "a", count: 40), subject: "Keep Task routing stable",
                author: "Fixture contributor", committedAt: now - 1_000)],
            contributors: [.init(name: "Fixture contributor", commits: 17)], contributorCount: 1, observedAt: now)]
        model.sessions.append(.init(sessionId: "other-native", agent: "codex", title: "Pairing API review",
            cwd: "/fixture", state: "working", startedAt: now - 500, lastActivityAt: now,
            tokensSession: 0, tokensLastTurn: 0))
        model.meshSnapshots[mesh.projectId] = mesh
        model.meshSnapshots[linked.projectId] = linked
        #endif
    }
}
