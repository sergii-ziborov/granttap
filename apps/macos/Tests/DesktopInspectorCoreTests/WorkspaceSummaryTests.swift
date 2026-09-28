import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func workspaceGroupsObservedActivityWithoutInventingTaskState() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "events": [
            row(1, task: "task-a", tool: "rg", phase: "reported_success"),
            row(2, task: "task-b", tool: "git", phase: "change_observed"),
            row(3, task: "task-a", tool: "rg", phase: "reported_failure"),
        ],
        "next_sequence": 3, "previous_sequence": 1,
        "has_more": false, "has_older": false,
    ])
    let page = try JSONDecoder().decode(InspectorInvocationPage.self, from: data)
    let summary = WorkspaceSummary(page: page)
    #expect(summary.tasks.map(\.taskId) == ["task-a", "task-b"])
    #expect(summary.tasks[0].eventCount == 2)
    #expect(summary.tasks[0].latestPhase == "Reported failure")
    #expect(summary.tools.map(\.name) == ["rg", "git"])
    #expect(summary.tools[0].count == 2)
    #expect(summary.isIncomplete == false)
}

private func row(_ sequence: Int, task: String, tool: String,
                 phase: String) -> [String: Any] {
    ["sequence": sequence, "event": [
        "event_id": "event-\(sequence)", "project_id": "project-a", "task_id": task,
        "provider": "codex", "tool_name": tool, "phase": phase,
        "source": "provider_report", "occurred_at": sequence,
        "policy_revision": NSNull(),
    ]]
}
