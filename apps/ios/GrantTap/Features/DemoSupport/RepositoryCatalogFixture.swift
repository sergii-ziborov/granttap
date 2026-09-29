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
            title: "Pairing API review", goal: "", state: "planned", createdAt: now - 500, updatedAt: now)]
        linked.executions = [.init(taskId: "other-scope-chat", sessionId: "other-native",
            provider: "codex", computerId: "Workstation", workspace: "/fixture",
            repositoryId: runtime, startedAt: now - 500, endedAt: now)]
        model.meshSnapshots[mesh.projectId] = mesh
        model.meshSnapshots[linked.projectId] = linked
        #endif
    }
}
