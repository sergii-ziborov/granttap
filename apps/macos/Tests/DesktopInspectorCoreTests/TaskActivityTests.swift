import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func taskConversationRequiresExactProjectAndTask() throws {
    let query = EngineQuery.taskActivity(projectId: "project", taskId: "task")
    let payload = Data(#"{"protocol_version":1,"request_id":"activity","status":"ok","result":{"operation":"desktop.task_activity","project_id":"project","task_id":"task","session_id":"session","agent":"codex","state":"working","entries":[{"id":"entry","kind":"message","text":"Synthetic reply","created_at":2,"tool_name":null,"summary":null}],"truncated":false}}"#.utf8)
    let result = try EngineCodec.result(payload, for: query, requestId: "activity")
    let activity = try JSONDecoder().decode(TaskActivitySnapshot.self, from: result)
    #expect(activity.session_id == "session")
    #expect(activity.entries.first?.text == "Synthetic reply")

    #expect(throws: EngineClientError.incompatibleResponse) {
        _ = try EngineCodec.result(payload, for: .taskActivity(projectId: "other", taskId: "task"),
                                   requestId: "activity")
    }
    #expect(throws: EngineClientError.incompatibleResponse) {
        _ = try EngineCodec.result(payload, for: .taskActivity(projectId: "project", taskId: "other"),
                                   requestId: "activity")
    }
}
