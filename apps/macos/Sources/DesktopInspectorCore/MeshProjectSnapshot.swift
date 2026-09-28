import Foundation

public struct MeshProjectSnapshot: Decodable, Sendable {
    public struct Task: Decodable, Sendable, Identifiable {
        public let task_id: String
        public let title: String
        public let state: String
        public let updated_at: Double
        public let provider: String?
        public let has_open_execution: Bool?
        public let last_execution_active_at: Double?
        public var id: String { task_id }
    }

    public let project_id: String
    public let tasks: [Task]
}

public struct MeshWorkspaceSummary: Decodable, Sendable {
    public struct Task: Decodable, Sendable, Identifiable {
        public let project_id: String
        public let project_name: String
        public let task_id: String
        public let title: String
        public let state: String
        public let updated_at: Double
        public let provider: String?
        public let has_open_execution: Bool?
        public let last_execution_active_at: Double?
        public var id: String { "\(project_id):\(task_id)" }
    }

    public let project_count: Int
    public let task_count: Int
    public let tasks: [Task]
}

enum MeshProjectCodec {
    static func matches(_ result: [String: Any], projectId: String) -> Bool {
        guard result["project_id"] as? String == projectId,
              let tasks = result["tasks"] as? [[String: Any]], tasks.count <= 64 else {
            return false
        }
        return tasks.allSatisfy(matchesTask)
    }

    static func matchesTask(_ task: [String: Any]) -> Bool {
        let states: Set<String> = ["planned", "working", "blocked", "needs_user",
                                   "handoff", "completed", "failed"]
        let providers: Set<String> = ["claude", "codex", "cursor", "grok", "grok_bot"]
            guard let id = task["task_id"] as? String, !id.isEmpty, id.utf8.count <= 128,
                  let title = task["title"] as? String, !title.isEmpty, title.utf16.count <= 160,
                  let state = task["state"] as? String, states.contains(state),
                  let updated = task["updated_at"] as? NSNumber, updated.doubleValue >= 0 else {
                return false
            }
            if let open = task["has_open_execution"], !(open is Bool) { return false }
            if let active = task["last_execution_active_at"], !(active is NSNull) {
                guard let time = active as? NSNumber, time.doubleValue >= 0 else { return false }
            }
            if let provider = task["provider"] as? String { return providers.contains(provider) }
            return task["provider"] is NSNull
    }
}

enum MeshWorkspaceCodec {
    static func matches(_ result: [String: Any]) -> Bool {
        guard let projects = result["project_count"] as? Int, projects >= 0,
              let taskCount = result["task_count"] as? Int, taskCount >= 0,
              let tasks = result["tasks"] as? [[String: Any]], tasks.count <= 256,
              tasks.count <= taskCount else { return false }
        return tasks.allSatisfy { task in
            guard let projectId = task["project_id"] as? String,
                  !projectId.isEmpty, projectId.utf8.count <= 128,
                  let projectName = task["project_name"] as? String,
                  !projectName.isEmpty, projectName.utf16.count <= 160 else { return false }
            return MeshProjectCodec.matchesTask(task)
        }
    }
}
