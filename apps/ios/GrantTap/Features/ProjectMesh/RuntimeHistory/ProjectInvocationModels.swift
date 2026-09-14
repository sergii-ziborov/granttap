import Foundation

/// A content-free fact about one native tool call. The computer's Engine owns
/// durable history; the phone holds a bounded, encrypted-in-transit projection.
struct ProjectInvocationEvent: Codable, Equatable, Identifiable {
    let event_id: String
    let invocation_id: String
    let project_id: String
    let task_id: String
    let execution_id: String
    let provider: String
    let native_call_id: String
    let session_id: String?
    let tool_name: String
    let phase: String
    let source: String
    let occurred_at: Double
    let repository_id: String?
    let worktree: String?
    let resource: String?
    let revision: String?
    let content_hash: String?
    let capability_artifact_hash: String?
    let policy_revision: Double?
    let policy_rule_id: String?
    var id: String { event_id }

    var isWellFormed: Bool {
        let phases: Set<String> = ["requested", "reported_success", "reported_failure",
                                   "reported_unknown", "denied", "change_observed", "source_gap"]
        let sources: Set<String> = ["transcript", "hook", "filesystem", "scanner"]
        guard phases.contains(phase), sources.contains(source),
              occurred_at.isFinite, occurred_at >= 0,
              [event_id, invocation_id, project_id, task_id, execution_id,
               provider, native_call_id, tool_name].allSatisfy({ !$0.isEmpty && $0.count <= 160 }),
              [session_id, repository_id, worktree, resource, revision, policy_rule_id]
                .compactMap({ $0 }).allSatisfy({ !$0.isEmpty && $0.count <= 512 }) else { return false }
        let sha256Pattern = "^[a-fA-F0-9]{64}$"
        guard [content_hash, capability_artifact_hash].compactMap({ $0 }).allSatisfy({
            $0.range(of: sha256Pattern, options: .regularExpression) != nil
        }) else { return false }
        if phase == "change_observed" {
            return source == "filesystem" && repository_id != nil && resource != nil
                && revision != nil && content_hash != nil
        }
        return true
    }
}

struct ProjectInvocationQuery: Codable {
    let type: String
    let sessionId: String
    let projectId: String
    let taskId: String
    let requestId: String
    let tail: Bool?
    let beforeSequence: Int?
    let afterSequence: Int?
    let limit: Int
}

struct ProjectInvocationRow: Codable, Equatable {
    let sequence: Int
    let event: ProjectInvocationEvent
}

struct ProjectInvocationPage: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    let taskId: String
    let requestId: String
    let sourceEndpointId: String
    let availability: String
    let events: [ProjectInvocationRow]
    let nextSequence: Int
    let previousSequence: Int
    let hasMore: Bool
    let hasOlder: Bool
    let generatedAt: Double

    var isWellFormed: Bool {
        guard type == "mesh.invocation.page", sessionId == projectId,
              !projectId.isEmpty, !taskId.isEmpty, !requestId.isEmpty,
              !sourceEndpointId.isEmpty, ["ready", "unavailable"].contains(availability),
              events.count <= 16, nextSequence >= 0, previousSequence >= 0,
              generatedAt.isFinite, generatedAt >= 0,
              availability != "unavailable" || events.isEmpty else { return false }
        var previous = 0
        for row in events {
            guard row.sequence > previous, row.sequence <= nextSequence,
                  row.event.project_id == projectId, row.event.task_id == taskId,
                  row.event.isWellFormed else { return false }
            previous = row.sequence
        }
        return true
    }
}

struct ProjectInvocationRecord: Identifiable, Equatable {
    let room: String
    let sequence: Int
    let event: ProjectInvocationEvent
    var id: String { "\(room)\u{1f}\(event.event_id)" }
}
