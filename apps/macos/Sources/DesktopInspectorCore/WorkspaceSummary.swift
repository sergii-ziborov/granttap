import Foundation

public struct WorkspaceSummary: Sendable {
    public struct TaskActivity: Sendable, Identifiable {
        public let taskId: String
        public let provider: String
        public let latestPhase: String
        public let latestTool: String
        public let latestAt: UInt64
        public let eventCount: Int
        public var id: String { taskId }
    }

    public struct ToolActivity: Sendable, Identifiable {
        public let name: String
        public let count: Int
        public var id: String { name }
    }

    public let tasks: [TaskActivity]
    public let tools: [ToolActivity]
    public let eventCount: Int
    public let isIncomplete: Bool

    public init(page: InspectorInvocationPage?) {
        guard let page else {
            tasks = []
            tools = []
            eventCount = 0
            isIncomplete = true
            return
        }
        let rows = page.events
        tasks = Dictionary(grouping: rows, by: { $0.event.task_id })
            .compactMap { taskId, events -> TaskActivity? in
                guard let latest = events.max(by: { $0.sequence < $1.sequence }) else { return nil }
                return TaskActivity(taskId: taskId, provider: latest.event.provider,
                                    latestPhase: latest.event.phaseLabel,
                                    latestTool: latest.event.tool_name,
                                    latestAt: latest.event.occurred_at,
                                    eventCount: events.count)
            }
            .sorted { $0.latestAt == $1.latestAt
                ? $0.taskId < $1.taskId : $0.latestAt > $1.latestAt }
        tools = Dictionary(grouping: rows, by: { $0.event.tool_name })
            .map { ToolActivity(name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        eventCount = rows.count
        isIncomplete = page.has_older || page.has_more
    }
}
