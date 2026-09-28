import Foundation

enum EngineHistoryCodec {
    static func matches(_ result: [String: Any], query: EngineQuery,
                        projectId: String) -> Bool {
        guard let page = result["page"] as? [String: Any] else { return false }
        switch query {
        case .knowledge:
            return matchesKnowledge(page, query: query, projectId: projectId)
        case .invocations:
            return matchesInvocations(page, query: query, projectId: projectId)
        default:
            return false
        }
    }

    private static func matchesKnowledge(_ page: [String: Any], query: EngineQuery,
                                         projectId: String) -> Bool {
        guard page["project_id"] as? String == projectId,
              let entries = page["entries"] as? [[String: Any]], entries.count <= 24,
              let incomplete = page["incomplete"] as? Bool else { return false }
        let next = page["next_before_version"] as? UInt64
        if incomplete && (entries.isEmpty || next == nil || next == 0) { return false }
        var prior = query.cursor ?? UInt64.max
        for entry in entries {
            guard entry["project_id"] as? String == projectId,
                  let visibility = entry["visibility"] as? String,
                  let taskId = entry["task_id"] as? String,
                  let version = entry["stream_version"] as? UInt64,
                  version < prior else { return false }
            prior = version
            if visibility == "project" { continue }
            if visibility != "task" || query.taskId == nil || taskId != query.taskId {
                return false
            }
        }
        if incomplete && next != prior { return false }
        return true
    }

    private static func matchesInvocations(_ page: [String: Any], query: EngineQuery,
                                           projectId: String) -> Bool {
        guard let events = page["events"] as? [[String: Any]], events.count <= 32,
              page["has_older"] is Bool, page["has_more"] is Bool,
              let previous = page["previous_sequence"] as? UInt64,
              let next = page["next_sequence"] as? UInt64 else { return false }
        if page["has_older"] as? Bool == true && (events.isEmpty || previous == 0) {
            return false
        }
        var prior: UInt64 = 0
        for row in events {
            guard let sequence = row["sequence"] as? UInt64,
                  sequence > prior, sequence <= next,
                  let event = row["event"] as? [String: Any],
                  event["project_id"] as? String == projectId,
                  let taskId = event["task_id"] as? String else { return false }
            if let expected = query.taskId, taskId != expected { return false }
            if let cursor = query.cursor, sequence >= cursor { return false }
            prior = sequence
        }
        if let first = events.first?["sequence"] as? UInt64, first != previous {
            return false
        }
        if let last = events.last?["sequence"] as? UInt64, last != next {
            return false
        }
        return true
    }
}
