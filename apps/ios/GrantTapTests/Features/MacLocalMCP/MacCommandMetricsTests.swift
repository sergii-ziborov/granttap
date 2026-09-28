#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class MacCommandMetricsTests: XCTestCase {
    func testLocalCommandTelemetrySurvivesDesktopProjectionAndWireRoundTrip() throws {
        let data = Data("""
        {"operation":"desktop.task_activity","project_id":"p","task_id":"t","session_id":"s",
         "agent":"claude","state":"idle","truncated":false,"entries":[
          {"id":"call","kind":"tool","text":"Bash: test","created_at":2,"tool_name":"Bash",
           "duration_ms":10000,"estimated_context_tokens":320,
           "capabilities":[{"kind":"cli","name":"test","toolName":"Bash","outcome":"success",
              "resource":{"attribution":"attributed","cpuTimeMs":7500,"peakRssBytes":300000000,"sampleWindowMs":10000}}]}
        ]}
        """.utf8)
        let response = try JSONDecoder().decode(MacLocalTaskActivity.self, from: data)
        let session = SessionInfo(sessionId: "s", agent: "claude", projectId: "p", taskId: "t",
            state: "idle", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        let model = AppModel()
        MacLocalProjection.apply(response, for: session, to: model)
        let entry = try XCTUnwrap(model.activities["s"]?.entries.first)
        XCTAssertEqual(entry.durationMs, 10000)
        XCTAssertEqual(entry.estimatedContextTokens, 320)
        XCTAssertEqual(entry.capabilities?.first?.resource?.cpuTimeMs, 7500)
        XCTAssertEqual(entry.capabilities?.first?.resource?.sampleWindowMs, 10000)
        XCTAssertEqual(entry.capabilities?.first?.resource?.peakRssBytes, 300000000)
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded, entry)
        let sparse = try JSONDecoder().decode(MacLocalTaskActivity.self, from: Data("""
        {"operation":"desktop.task_activity","project_id":"p","task_id":"t","session_id":"s",
         "agent":"claude","state":"idle","truncated":false,"entries":[
          {"id":"call","kind":"tool","text":"Bash: test","created_at":2,"tool_name":"Bash"}]}
        """.utf8))
        MacLocalProjection.apply(sparse, for: session, to: model)
        XCTAssertEqual(model.activities["s"]?.entries.first?.capabilities?.first?.resource,
                       entry.capabilities?.first?.resource)
    }
}
#endif
