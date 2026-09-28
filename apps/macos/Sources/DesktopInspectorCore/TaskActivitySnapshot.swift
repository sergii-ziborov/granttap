import Foundation

public struct TaskActivitySnapshot: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Identifiable {
        public let id: String
        public let kind: String
        public let text: String
        public let created_at: Double
        public let tool_name: String?
        public let summary: String?
    }

    public let project_id: String
    public let task_id: String
    public let session_id: String?
    public let agent: String?
    public let state: String?
    public let entries: [Entry]
    public let truncated: Bool
}

enum TaskActivityCodec {
    static func matches(_ result: [String: Any], projectId: String, taskId: String) -> Bool {
        guard result["project_id"] as? String == projectId,
              result["task_id"] as? String == taskId,
              result["truncated"] is Bool,
              let entries = result["entries"] as? [[String: Any]], entries.count <= 48
        else { return false }
        if let session = result["session_id"], !(session is NSNull) {
            guard let value = session as? String, !value.isEmpty,
                  value.utf8.count <= 256 else { return false }
        }
        return entries.allSatisfy { entry in
            guard let id = entry["id"] as? String, !id.isEmpty, id.utf8.count <= 256,
                  let kind = entry["kind"] as? String,
                  ["user", "message", "tool", "final", "status"].contains(kind),
                  let body = entry["text"] as? String, body.utf16.count <= 2_048,
                  let timestamp = entry["created_at"] as? NSNumber,
                  timestamp.doubleValue >= 0 else { return false }
            return true
        }
    }
}
