import Foundation

/// UI request states use the isolated demo Mesh; no account or relay is changed.
enum GraphBuildFixture {
    @MainActor
    static func apply(to model: AppModel, mesh: inout ProjectMeshSnapshot, at now: Double) {
        #if DEBUG
        guard let state = ProcessInfo.processInfo.environment["GRANTTAP_TEST_GRAPH_BUILD"] else { return }
        model.projectGraphAttemptAt[mesh.projectId] = now
        if state == "cached-pending" {
            mesh.repositoryGraphs = [AppModelDemoMeshFixtures.architectureGraph()]
        } else if state == "unavailable" {
            var report = AppModelDemoMeshFixtures.architectureGraph()
            report.analysisStatus = "UNAVAILABLE"
            report.analysisErrorCode = "REPOSITORY_IDENTITY_MISMATCH"
            report.sourceRevision = String(repeating: "b", count: 40)
            mesh.repositoryGraphs = [report]
        } else {
            mesh.repositoryGraphs = []
        }
        model.meshSnapshots[mesh.projectId] = mesh
        if state == "idle" {
            model.projectGraphRequests[mesh.projectId] = nil
        } else {
            var request = ProjectGraphRequest(createdAt: now)
            if state == "failure" || state == "unavailable" {
                request.pending = false
                request.result = .failed
            }
            model.projectGraphRequests[mesh.projectId] = request
        }
        #endif
    }
}
