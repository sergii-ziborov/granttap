import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func coverageReadUsesProjectScopeAndRejectsForeignReceipts() throws {
    let query = EngineQuery.coverage("project-a")
    let frame = try EngineCodec.encode(query, requestId: "coverage-read")
    let request = try #require(JSONSerialization.jsonObject(with: frame.dropFirst(4))
                               as? [String: Any])
    #expect(request["operation"] as? String == "policy.coverage")
    #expect((request["input"] as? [String: Any])?["project_id"] as? String == "project-a")

    let valid = coverage(project: "project-a", endpointProject: "project-a", revision: 3)
    let result = try EngineCodec.result(reply(valid), for: query, requestId: "coverage-read")
    let decoded = try JSONDecoder().decode(CoverageEnvelope.self, from: result)
    #expect(decoded.coverage.required_capabilities == [.shell])
    #expect(decoded.coverage.endpoints.first?.capabilities.first?.status == .enforced)
    #expect(decoded.coverage.strict_ready)

    let foreign = coverage(project: "project-a", endpointProject: "project-b", revision: 3)
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(reply(foreign), for: query, requestId: "coverage-read")
    }
    let stale = coverage(project: "project-a", endpointProject: "project-a", revision: 2)
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(reply(stale), for: query, requestId: "coverage-read")
    }
    let invalidTime = coverage(project: "project-a", endpointProject: "project-a",
                               revision: 3, observedAt: -1)
    #expect(throws: EngineClientError.self) {
        _ = try EngineCodec.result(reply(invalidTime), for: query, requestId: "coverage-read")
    }
    let unsetPolicy: [String: Any] = [
        "project_id": "project-a", "policy_revision": 0,
        "enforcement": "best_available", "required_capabilities": [],
        "endpoints": [], "strict_ready": true,
    ]
    _ = try EngineCodec.result(reply(unsetPolicy), for: query, requestId: "coverage-read")
}

private struct CoverageEnvelope: Decodable { let coverage: InspectorPolicyCoverage }

private func coverage(project: String, endpointProject: String,
                      revision: Int, observedAt: Int = 100) -> [String: Any] {
    ["project_id": project, "policy_revision": 3, "enforcement": "strict",
     "required_capabilities": ["shell"], "strict_ready": true,
     "endpoints": [["project_id": endpointProject, "policy_revision": revision,
                    "endpoint_id": "computer-a", "provider": "codex",
                    "capabilities": [["kind": "shell", "status": "enforced"]],
                    "observed_at": observedAt]]]
}

private func reply(_ coverage: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "protocol_version": 1, "request_id": "coverage-read", "status": "ok",
        "result": ["operation": "policy.coverage", "coverage": coverage],
    ])
}
