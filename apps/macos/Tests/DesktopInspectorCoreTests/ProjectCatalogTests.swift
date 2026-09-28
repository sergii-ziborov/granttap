import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func projectCatalogUsesBoundedCursorAndRejectsForeignPages() throws {
    let query = EngineQuery.projects(afterProjectId: "beta")
    let frame = try EngineCodec.encode(query, requestId: "catalog")
    let request = try #require(JSONSerialization.jsonObject(with: frame.dropFirst(4))
                               as? [String: Any])
    #expect(request["operation"] as? String == "project.list")
    let input = try #require(request["input"] as? [String: Any])
    #expect(input["limit"] as? Int == 50)
    #expect(input["after_project_id"] as? String == "beta")
    let valid = response(projects: [project("gamma")], next: nil)
    _ = try EngineCodec.result(valid, for: query, requestId: "catalog")
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(response(projects: [project("alpha")], next: nil),
                                   for: query, requestId: "catalog")
    }
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(response(projects: [project("gamma")], next: "gamma"),
                                   for: query, requestId: "catalog")
    }
}

private func project(_ id: String) -> [String: Any] {
    ["project_id": id, "name": "Project \(id)", "created_at": 1]
}

private func response(projects: [[String: Any]], next: String?) -> Data {
    let page: [String: Any] = [
        "projects": projects,
        "next_after_project_id": next as Any? ?? NSNull(),
    ]
    return try! JSONSerialization.data(withJSONObject: [
        "protocol_version": 1, "request_id": "catalog", "status": "ok",
        "result": ["operation": "project.listed", "page": page],
    ])
}
