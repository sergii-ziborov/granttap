import Foundation

public enum InspectorCapabilityKind: String, Decodable, Hashable, Sendable {
    case agent, mcp, skill, shell, script, file_write, deploy, network

    public var label: String {
        switch self {
        case .file_write: "File write"
        default: rawValue.capitalized
        }
    }
}

public enum InspectorEnforcementStatus: String, Decodable, Sendable {
    case enforced, observed, unsupported, unknown

    public var label: String { rawValue.capitalized }
}

public struct InspectorCapabilityCoverage: Decodable, Sendable {
    public let kind: InspectorCapabilityKind
    public let status: InspectorEnforcementStatus
}

public struct InspectorPolicyAcknowledgement: Decodable, Sendable, Identifiable {
    public let project_id: String
    public let policy_revision: UInt64
    public let endpoint_id: String
    public let provider: String
    public let capabilities: [InspectorCapabilityCoverage]
    public let observed_at: UInt64

    public var id: String { "\(endpoint_id):\(provider)" }
}

public struct InspectorPolicyCoverage: Decodable, Sendable {
    public let project_id: String
    public let policy_revision: UInt64
    public let enforcement: String
    public let required_capabilities: [InspectorCapabilityKind]
    public let endpoints: [InspectorPolicyAcknowledgement]
    public let strict_ready: Bool
}
