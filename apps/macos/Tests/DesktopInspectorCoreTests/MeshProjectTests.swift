import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func meshTasksKeepProjectScopeAndObservedState() throws {
    let response = Data(#"{"protocol_version":1,"request_id":"mesh","status":"ok","result":{"operation":"desktop.project","project_id":"p","tasks":[{"task_id":"t","title":"Fix Mac","state":"working","updated_at":5,"provider":"codex","has_open_execution":true,"last_execution_active_at":4}]}}"#.utf8)
    let result = try EngineCodec.result(response, for: .meshProject("p"), requestId: "mesh")
    let project = try JSONDecoder().decode(MeshProjectSnapshot.self, from: result)
    #expect(project.project_id == "p")
    #expect(project.tasks.first?.title == "Fix Mac")
    #expect(project.tasks.first?.state == "working")
    #expect(project.tasks.first?.has_open_execution == true)
    #expect(project.tasks.first?.last_execution_active_at == 4)

    #expect(throws: EngineClientError.incompatibleResponse) {
        _ = try EngineCodec.result(response, for: .meshProject("elsewhere"), requestId: "mesh")
    }

    let malformed = Data(#"{"protocol_version":1,"request_id":"mesh","status":"ok","result":{"operation":"desktop.project","project_id":"p","tasks":[{"task_id":"t","title":"Fix Mac","state":"working","updated_at":5,"provider":"codex","has_open_execution":"yes"}]}}"#.utf8)
    #expect(throws: EngineClientError.incompatibleResponse) {
        _ = try EngineCodec.result(malformed, for: .meshProject("p"), requestId: "mesh")
    }
}

@Test func workspaceTasksPreserveProjectIdentity() throws {
    let response = Data(#"{"protocol_version":1,"request_id":"workspace","status":"ok","result":{"operation":"desktop.workspace","project_count":2,"task_count":1,"tasks":[{"project_id":"p","project_name":"Project","task_id":"t","title":"Fix Mac","state":"working","updated_at":5,"provider":null,"has_open_execution":false,"last_execution_active_at":null}]}}"#.utf8)
    let result = try EngineCodec.result(response, for: .workspace, requestId: "workspace")
    let workspace = try JSONDecoder().decode(MeshWorkspaceSummary.self, from: result)
    #expect(workspace.project_count == 2)
    #expect(workspace.tasks.first?.project_id == "p")
    #expect(workspace.tasks.first?.has_open_execution == false)
}
