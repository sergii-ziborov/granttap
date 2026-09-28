import Foundation
import Testing
@testable import DesktopInspectorCore

/** Opt-in wire check against this Mac's installed MCP; no Project data is logged. */
@Test func installedMCPFeedsDesktopCatalogAndTaskState() async throws {
    guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_LIVE_MCP"] == "1" else { return }
    let status = try await LocalMCPStatus.fetch()
    let path = try #require(status.desktopEngineSocket)
    let service = InspectorService(client: EngineClient(socketPath: path))
    let page: InspectorProjectPage
    do { page = try service.projectPage() }
    catch { Issue.record("Live MCP catalog read failed: \(error)"); return }
    let project = try #require(page.projects.first)
    let mesh: MeshProjectSnapshot
    do { mesh = try service.meshProject(projectId: project.project_id) }
    catch { Issue.record("Live MCP Task read failed: \(error)"); return }
    #expect(mesh.project_id == project.project_id)
    #expect(mesh.tasks.count <= 64)
    let workspace: MeshWorkspaceSummary
    do { workspace = try service.workspaceSummary() }
    catch { Issue.record("Live MCP workspace read failed: \(error)"); return }
    #expect(workspace.project_count >= page.projects.count)
    #expect(workspace.task_count >= workspace.tasks.count)
    if workspace.task_count <= 256 {
        #expect(workspace.tasks.count == workspace.task_count)
    }
    if let live = workspace.tasks.first(where: {
        $0.has_open_execution == true && $0.provider == "codex"
    }) {
        var activity: TaskActivitySnapshot?
        var lastFailure = "none"
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
            do {
                activity = try InspectorService(client: EngineClient(socketPath: path,
                                                                     timeoutSeconds: 5.5))
                    .taskActivity(projectId: live.project_id, taskId: live.task_id)
            } catch { lastFailure = String(describing: error) }
            if activity != nil { break }
        }
        let found = try #require(activity, "Live MCP conversation read failed: \(lastFailure)")
        #expect(found.project_id == live.project_id)
        #expect(found.task_id == live.task_id)
        #expect(found.entries.count <= 48)
        #expect(!found.entries.isEmpty)
    }
}
