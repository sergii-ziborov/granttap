import Foundation

enum ProjectCapabilityKind: String, Codable, CaseIterable, Identifiable {
    case agent, mcp, skill, shell, script
    case fileWrite = "file_write"
    case deploy, network

    var id: String { rawValue }
}

enum ProjectFingerprintConfidence: String, Codable, CaseIterable {
    case exact, strong
    case nameOnly = "name_only"
    case unknown
}

enum ProjectFingerprintMatch: String, Codable {
    case exact
    case changedFrom = "changed_from"
    case confidence
}

struct ProjectCapabilityFingerprint: Codable, Equatable {
    let kind: ProjectCapabilityKind
    let displayName: String
    var provider: String? = nil
    var origin: String? = nil
    var publisher: String? = nil
    var version: String? = nil
    var transport: String? = nil
    var executablePathHash: String? = nil
    var configHash: String? = nil
    var scriptHash: String? = nil
    let confidence: ProjectFingerprintConfidence
}

struct ProjectFingerprintPredicate: Codable, Equatable {
    let match: ProjectFingerprintMatch
    var expected: ProjectCapabilityFingerprint? = nil
    var value: ProjectFingerprintConfidence? = nil
}

struct ProjectPolicySelector: Codable, Equatable {
    var kind: ProjectCapabilityKind? = nil
    var displayName: String? = nil
    var provider: String? = nil
    var origin: String? = nil
    var fingerprint: ProjectFingerprintPredicate? = nil
}

struct ProjectPolicyConditions: Codable, Equatable {
    var endpointIds: [String]
    var providers: [String]
    var impact: String? = nil
}

struct ProjectPolicyRule: Codable, Equatable, Identifiable {
    let ruleId: String
    let projectId: String
    var selector: ProjectPolicySelector
    var effect: ProjectPolicyEffect
    var conditions: ProjectPolicyConditions
    var revision: Int
    let createdBy: String
    var id: String { ruleId }
}

enum ProjectExecutionMode: String, Codable, CaseIterable {
    case distributed
    case pinned
}

enum HostGrantStatus: String, Codable {
    case none
    case pending
    case applied
    case unavailable
}

enum ExecutionOfflineBehavior: String, Codable, CaseIterable {
    case reject
    case queueUntilDeadline
}

struct ProjectExecutionPolicy: Codable, Equatable {
    var mode: ProjectExecutionMode
    var targetEndpointId: String? = nil
    var revision: Int
    var hostGrantId: String? = nil
    var hostGrantStatus: HostGrantStatus = .none
    var offlineBehavior: ExecutionOfflineBehavior = .reject
}

struct ProjectPolicy: Codable, Equatable {
    let projectId: String
    var revision: Int
    var enforcement: ProjectEnforcementMode
    var rules: [ProjectPolicyRule]
    var execution: ProjectExecutionPolicy? = nil
}

struct ProjectCapabilityCoverage: Codable, Equatable {
    let kind: ProjectCapabilityKind
    let status: ProjectPolicyCoverageStatus
}

struct ProjectPolicyAcknowledgement: Codable, Equatable, Identifiable {
    let projectId: String
    var policyRevision: Int
    let endpointId: String
    let provider: String
    var capabilities: [ProjectCapabilityCoverage]
    let observedAt: Double
    var id: String { "\(endpointId)\u{1f}\(provider)" }
}

struct ProjectPolicyCoverage: Codable, Equatable {
    let projectId: String
    var policyRevision: Int
    let enforcement: ProjectEnforcementMode
    let requiredCapabilities: [ProjectCapabilityKind]
    var endpoints: [ProjectPolicyAcknowledgement]
    let strictReady: Bool
}

struct ProjectPolicySet: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    let expectedRevision: Int
    let policy: ProjectPolicy
    /// Names this one edit, so a computer's answer to it can be told from
    /// the answer to another edit of the same revision.
    var requestId: String? = nil
    let createdAt: Double
}

/// Why a computer did not apply an edit the phone sent, and the revision it
/// actually holds, so the edit can be offered again on top of that.
struct ProjectPolicyRejected: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    let expectedRevision: Int
    var currentRevision: Int? = nil
    let reason: String
    var detail: String? = nil
    /// The edit this answers, echoed from a request that carried one.
    var requestId: String? = nil
    let generatedAt: Double
}

struct ProjectPolicyStatus: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    var policy: ProjectPolicy
    var coverage: ProjectPolicyCoverage
    let generatedAt: Double
}

struct ProjectPolicyAck: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    var acknowledgement: ProjectPolicyAcknowledgement
}
