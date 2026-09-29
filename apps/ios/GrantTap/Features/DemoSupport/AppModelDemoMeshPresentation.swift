import Foundation

@MainActor
extension AppModel {
    func applyDemoMeshPresentationFixtures(mesh: inout ProjectMeshSnapshot, at now: Double) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_SOLUTION"] == "1" {
            let linked = AppModelDemoMeshFixtures.linkedSnapshot(at: now)
            mesh.bindings = mesh.bindings?.filter {
                $0.repositoryId == mesh.project.canonicalRepositoryId
            }
            mesh.executions[0].repositoryId = linked.project.canonicalRepositoryId
            meshSnapshots[mesh.projectId] = mesh
            meshSnapshots[linked.projectId] = linked
        }
        TurnModelPickerFixture.apply(to: self, at: now)
        RepositoryCatalogFixture.apply(to: self, at: now)
        #endif
    }
}
