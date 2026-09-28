import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func historyQueriesBoundPagesAndKeepProjectKnowledgePublic() throws {
    let knowledge = try request(.knowledge(projectId: "project-a", taskId: nil,
                                            beforeVersion: nil))
    let input = try #require(knowledge["input"] as? [String: Any])
    #expect(knowledge["operation"] as? String == "memory.history")
    #expect(input["project_id"] as? String == "project-a")
    #expect(input["visibility"] as? String == "project")
    #expect(input["limit"] as? Int == 24)
    #expect(input["include_superseded"] as? Bool == false)

    let invocation = try request(.invocations(projectId: "project-a", taskId: "task-a",
                                              beforeSequence: 42))
    let cursor = try #require(invocation["input"] as? [String: Any])
    #expect(invocation["operation"] as? String == "invocation.history")
    #expect(cursor["task_id"] as? String == "task-a")
    #expect(cursor["before_sequence"] as? Int == 42)
    #expect(cursor["tail"] as? Bool == true)
    #expect(cursor["limit"] as? Int == 32)
}

@Test func historyResponseRejectsForeignProjectAndTaskPrivateRows() throws {
    let publicQuery = EngineQuery.knowledge(projectId: "project-a", taskId: nil,
                                            beforeVersion: nil)
    let taskQuery = EngineQuery.knowledge(projectId: "project-a", taskId: "task-a",
                                          beforeVersion: nil)
    let foreign = knowledgeRow(visibility: "task", taskId: "task-b")
    let response = envelope(operation: "memory.history", page: [
        "project_id": "project-a", "entries": [foreign],
        "next_before_version": NSNull(), "incomplete": false,
    ])
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(response, for: publicQuery, requestId: "r")
    }
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(response, for: taskQuery, requestId: "r")
    }
    let valid = envelope(operation: "memory.history", page: [
        "project_id": "project-a", "entries": [
            knowledgeRow(visibility: "project", taskId: "task-b")
                .merging(["stream_version": 0]) { _, new in new },
        ],
        "next_before_version": NSNull(), "incomplete": false,
    ])
    _ = try EngineCodec.result(valid, for: publicQuery, requestId: "r")
}

@Test func invocationResponseRejectsMismatchedTask() {
    let query = EngineQuery.invocations(projectId: "project-a", taskId: "task-a",
                                         beforeSequence: nil)
    let response = envelope(operation: "invocation.history", page: [
        "events": [["sequence": 7, "event": ["project_id": "project-a", "task_id": "task-b"]]],
        "next_sequence": 7, "has_more": false, "previous_sequence": 7, "has_older": false,
    ])
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(response, for: query, requestId: "r")
    }
}

private func request(_ query: EngineQuery) throws -> [String: Any] {
    let frame = try EngineCodec.encode(query, requestId: "r")
    return try #require(JSONSerialization.jsonObject(with: frame.dropFirst(4)) as? [String: Any])
}

private func envelope(operation: String, page: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "protocol_version": 1, "request_id": "r", "status": "ok",
        "result": ["operation": operation, "page": page],
    ])
}

private func knowledgeRow(visibility: String, taskId: String) -> [String: Any] {
    ["project_id": "project-a", "task_id": taskId, "visibility": visibility,
     "record_id": "record-a", "category": "decision", "content": "safe test content",
     "source": "user_decision", "source_ref": "source-a", "recorded_at": 1,
     "stream_version": 1]
}
