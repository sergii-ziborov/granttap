import Foundation

public struct InspectorKnowledgeRecord: Decodable, Sendable, Identifiable {
    public let project_id: String
    public let task_id: String
    public let record_id: String
    public let category: String
    public let content: String
    public let source: String
    public let source_ref: String
    public let visibility: String
    public let repository_id: String?
    public let commit_sha: String?
    public let recorded_at: UInt64
    public let stream_version: UInt64
    public var id: String { record_id }

    public var sourceLabel: String {
        switch source {
        case "agent_report": "Agent report · unverified"
        case "task_capsule": "Task capsule"
        case "observed_invocation": "Observed invocation"
        case "user_decision": "User decision"
        default: source
        }
    }
}

public struct InspectorKnowledgePage: Decodable, Sendable {
    public let project_id: String
    public var entries: [InspectorKnowledgeRecord]
    public var next_before_version: UInt64?
    public var incomplete: Bool
}

public struct InspectorInvocationEvent: Decodable, Sendable, Identifiable {
    public let event_id: String
    public let project_id: String
    public let task_id: String
    public let provider: String
    public let tool_name: String
    public let phase: String
    public let source: String
    public let occurred_at: UInt64
    public let policy_revision: UInt64?
    public var id: String { event_id }

    public var phaseLabel: String {
        switch phase {
        case "reported_success": "Reported success · unverified"
        case "reported_failure": "Reported failure"
        case "reported_unknown": "Reported unknown"
        case "change_observed": "Change observed"
        case "source_gap": "Source gap"
        default: phase.capitalized
        }
    }
}

public struct InspectorInvocationRow: Decodable, Sendable, Identifiable {
    public let sequence: UInt64
    public let event: InspectorInvocationEvent
    public var id: String { event.id }
}

public struct InspectorInvocationPage: Decodable, Sendable {
    public var events: [InspectorInvocationRow]
    public let next_sequence: UInt64
    public let has_more: Bool
    public var previous_sequence: UInt64
    public var has_older: Bool
}
