import Foundation

enum ProjectGovernanceWireValidator {
    private static let maxBytes = 64 * 1_024
    private static let maxRevision = 9_007_199_254_740_991
    private static let providers = Set(["claude", "codex", "cursor", "grok"])
    private static let impacts = Set(["any", "available", "missing"])

    static func validSet(_ value: ProjectPolicySet) -> Bool {
        value.type == "project.policy.set" && scope(value.sessionId, value.projectId)
            && revision(value.expectedRevision, allowZero: true)
            && timestamp(value.createdAt) && policy(value.policy, projectId: value.projectId)
            && value.policy.revision == value.expectedRevision + 1
            && (value.requestId.map(identifier) ?? true)
    }

    static func validStatus(_ value: ProjectPolicyStatus) -> Bool {
        value.type == "project.policy.status" && scope(value.sessionId, value.projectId)
            && timestamp(value.generatedAt) && policy(value.policy, projectId: value.projectId)
            && coverage(value.coverage, policy: value.policy)
    }

    static func validAck(_ value: ProjectPolicyAck) -> Bool {
        value.type == "project.policy.ack" && scope(value.sessionId, value.projectId)
            && acknowledgement(value.acknowledgement, projectId: value.projectId)
    }

    static func validSet(_ data: Data) -> Bool {
        decode(data, type: ProjectPolicySet.self, keys: [
            "type", "sessionId", "projectId", "expectedRevision", "policy", "createdAt",
        ], optional: ["requestId"]).map(validSet) ?? false
    }

    static func validStatus(_ data: Data) -> Bool {
        decode(data, type: ProjectPolicyStatus.self, keys: [
            "type", "sessionId", "projectId", "policy", "coverage", "generatedAt",
        ]).map(validStatus) ?? false
    }

    static func validAck(_ data: Data) -> Bool {
        decode(data, type: ProjectPolicyAck.self, keys: [
            "type", "sessionId", "projectId", "acknowledgement",
        ]).map(validAck) ?? false
    }

    private static let rejectionReasons = Set(["revision_mismatch", "engine_unavailable", "invalid_policy", "unknown"])

    static func validRejected(_ value: ProjectPolicyRejected) -> Bool {
        value.type == "project.policy.rejected" && scope(value.sessionId, value.projectId)
            && revision(value.expectedRevision, allowZero: true)
            && (value.currentRevision.map { revision($0, allowZero: true) } ?? true)
            && rejectionReasons.contains(value.reason)
            && (value.detail.map { !$0.isEmpty && $0.count <= 240 } ?? true)
            && (value.requestId.map(identifier) ?? true)
            && timestamp(value.generatedAt)
    }

    static func validRejected(_ data: Data) -> Bool {
        let required: Set<String> = ["type", "sessionId", "projectId", "expectedRevision", "reason", "generatedAt"]
        let optional: Set<String> = ["currentRevision", "detail", "requestId"]
        guard data.count <= maxBytes,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = withoutNulls(raw) as? [String: Any],
              required.isSubset(of: object.keys), Set(object.keys).isSubset(of: required.union(optional)),
              let decoded = try? JSONDecoder().decode(ProjectPolicyRejected.self, from: data) else { return false }
        return validRejected(decoded)
    }

    private static func decode<T: Decodable>(
        _ data: Data, type: T.Type, keys: Set<String>, optional: Set<String> = []
    ) -> T? {
        // A computer that says `"fingerprint": null` means the field is not
        // there. Reading the null as a value made the shape check refuse every
        // status the engine produced, and Governance said "no rules" while the
        // computer was enforcing two.
        guard data.count <= maxBytes,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = withoutNulls(raw) as? [String: Any],
              keys.isSubset(of: object.keys), Set(object.keys).isSubset(of: keys.union(optional)),
              strictNestedShapes(object),
              let decoded = try? JSONDecoder().decode(type, from: data) else { return nil }
        return decoded
    }

    /// Revision 0 is a Project the computer reports before any policy is
    /// authored. It is accepted so the editor can write the first revision;
    /// `validSet` still refuses to ever set revision 0 itself.
    private static func policy(_ value: ProjectPolicy, projectId: String) -> Bool {
        guard identifier(projectId), value.projectId == projectId,
              revision(value.revision, allowZero: true), value.rules.count <= 256,
              Set(value.rules.map(\.ruleId)).count == value.rules.count else { return false }
        return value.rules.allSatisfy { rule in
            identifier(rule.ruleId) && rule.projectId == projectId
                && rule.revision == value.revision && identifier(rule.createdBy)
                && selector(rule.selector) && conditions(rule.conditions)
        }
    }

    private static func selector(_ value: ProjectPolicySelector) -> Bool {
        optionalLabel(value.displayName) && optionalProvider(value.provider)
            && optionalText(value.origin, max: 512)
            && value.fingerprint.map(fingerprintPredicate) ?? true
    }

    private static func conditions(_ value: ProjectPolicyConditions) -> Bool {
        value.endpointIds.count <= 64 && value.providers.count <= 4
            && value.endpointIds.allSatisfy(identifier)
            && value.providers.allSatisfy { providers.contains($0) }
            && value.impact.map { impacts.contains($0) } ?? true
    }

    private static func fingerprintPredicate(_ value: ProjectFingerprintPredicate) -> Bool {
        switch value.match {
        case .confidence:
            return value.expected == nil && value.value != nil
        case .exact, .changedFrom:
            return value.value == nil && value.expected.map {
                fingerprint($0) && $0.confidence == .exact
                    && [$0.executablePathHash, $0.configHash, $0.scriptHash]
                        .contains { $0 != nil }
            } ?? false
        }
    }

    private static func fingerprint(_ value: ProjectCapabilityFingerprint) -> Bool {
        label(value.displayName) && optionalProvider(value.provider)
            && optionalText(value.origin, max: 512) && optionalLabel(value.publisher)
            && optionalLabel(value.version) && optionalLabel(value.transport)
            && [value.executablePathHash, value.configHash, value.scriptHash]
                .allSatisfy { $0.map(validHash) ?? true }
    }

    private static func coverage(_ value: ProjectPolicyCoverage, policy: ProjectPolicy) -> Bool {
        let endpointKeys = value.endpoints.map { $0.id }
        return value.projectId == policy.projectId && value.policyRevision == policy.revision
            && value.enforcement == policy.enforcement && value.requiredCapabilities.count <= 8
            && Set(value.requiredCapabilities).count == value.requiredCapabilities.count
            && value.endpoints.count <= 32 && Set(endpointKeys).count == endpointKeys.count
            && value.endpoints.allSatisfy {
                acknowledgement($0, projectId: policy.projectId)
                    && $0.policyRevision == policy.revision
            }
    }

    private static func acknowledgement(
        _ value: ProjectPolicyAcknowledgement, projectId: String
    ) -> Bool {
        // Revision zero is a Project whose policy has not been authored yet, and
        // a computer can acknowledge that state like any other. The policy
        // itself is accepted at zero; refusing it here made one endpoint saying
        // so enough to render the whole status unreadable, which is reported as
        // "Governance not reported" — on exactly the Projects where the first
        // policy still has to be written.
        value.projectId == projectId && revision(value.policyRevision, allowZero: true)
            && identifier(value.endpointId) && providers.contains(value.provider)
            && value.capabilities.count <= 8
            && Set(value.capabilities.map(\.kind)).count == value.capabilities.count
            && timestamp(value.observedAt)
    }

    private static func scope(_ sessionId: String, _ projectId: String) -> Bool {
        sessionId == projectId && identifier(projectId)
    }

    private static func revision(_ value: Int, allowZero: Bool = false) -> Bool {
        value <= maxRevision && (allowZero ? value >= 0 : value > 0)
    }

    private static func timestamp(_ value: Double) -> Bool { value.isFinite && value >= 0 }
    private static func identifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 128
    }

    private static func optionalLabel(_ value: String?) -> Bool {
        value.map(label) ?? true
    }

    private static func label(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 160
    }

    private static func optionalText(_ value: String?, max: Int) -> Bool {
        guard let value else { return true }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.count <= max
    }

    private static func optionalProvider(_ value: String?) -> Bool {
        value.map { providers.contains($0) } ?? true
    }

    private static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }
}
