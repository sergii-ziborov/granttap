import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func versionRequestUsesBoundedBigEndianFrame() throws {
    let frame = try EngineCodec.encode(.version, requestId: "request-1")
    let length = frame.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    #expect(length == frame.count - 4)
    let body = try #require(JSONSerialization.jsonObject(with: frame.dropFirst(4)) as? [String: Any])
    #expect(body["protocol_version"] as? Int == 1)
    #expect(body["request_id"] as? String == "request-1")
    #expect(body["operation"] as? String == "engine.version")
    #expect(body["input"] == nil)
}

@Test func responseMustMatchRequestOperationAndProject() throws {
    let query = EngineQuery.project("project-a")
    let valid = payload(id: "r", operation: "project.found", content: [
        "project": ["project_id": "project-a", "name": "A", "created_at": 1],
    ])
    _ = try EngineCodec.result(valid, for: query, requestId: "r")
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(valid, for: query, requestId: "other")
    }
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(payload(id: "r", operation: "policy.found", content: [:]),
                                   for: query, requestId: "r")
    }
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(payload(id: "r", operation: "project.found", content: [
            "project": ["project_id": "project-b", "name": "B", "created_at": 1],
        ]), for: query, requestId: "r")
    }
}

@Test func remoteErrorDoesNotExposeServerText() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "protocol_version": 1, "request_id": "r", "status": "error",
        "error": ["code": "DENIED", "message": "private prompt content"],
    ])
    do {
        _ = try EngineCodec.result(data, for: .version, requestId: "r")
        Issue.record("Expected a remote error")
    } catch {
        #expect(!String(describing: error).contains("private prompt content"))
    }
}

@Test func folderLookupUsesTheExistingProjectResolutionContract() throws {
    let query = EngineQuery.resolveFolder("/work/repository")
    let frame = try EngineCodec.encode(query, requestId: "lookup")
    let request = try #require(JSONSerialization.jsonObject(with: frame.dropFirst(4))
                               as? [String: Any])
    #expect(request["operation"] as? String == "project.resolve")
    #expect((request["input"] as? [String: Any])?["local_root"] as? String == "/work/repository")
    let reply = payload(id: "lookup", operation: "project.resolved", content: [
        "resolution": ["project_id": "project-a", "compatibility_mode": false],
    ])
    _ = try EngineCodec.result(reply, for: query, requestId: "lookup")
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(payload(id: "lookup", operation: "project.resolved",
                                           content: ["resolution": ["project_id": "project-a",
                                                                   "compatibility_mode": true]]),
                                   for: query, requestId: "lookup")
    }
}

private func payload(id: String, operation: String, content: [String: Any]) -> Data {
    var result = content
    result["operation"] = operation
    return try! JSONSerialization.data(withJSONObject: [
        "protocol_version": 1, "request_id": id, "status": "ok", "result": result,
    ])
}
