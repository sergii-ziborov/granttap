import Foundation

enum ProjectGovernanceLogic {
    static func merged(
        current: ProjectGovernanceProjection?, status: ProjectPolicyStatus
    ) -> ProjectGovernanceProjection? {
        guard ProjectGovernanceWireValidator.validStatus(status) else { return current }
        let incoming = projection(status)
        guard let current else { return incoming }
        guard current.projectId == status.projectId else { return current }
        // Two different policies at one revision mean a publisher is stale, and
        // holding what is already here is right — a diverging peer must not be
        // able to overwrite the Project's policy without moving the revision.
        //
        // But holding it *forever* is what left the phone stuck: a computer
        // that read the policy again and published a corrected copy under the
        // same revision was refused for good, so the screen said "0 rules"
        // while rules were enforced, and Save stayed grey because the draft
        // matched the stale copy. A strictly later reading is not a diverging
        // peer, it is the same computer knowing better.
        if let canonical = current.policy, canonical != status.policy,
           status.generatedAt <= current.updatedAt {
            return current
        }
        let rows = mergedCoverage(current.coverage, incoming.coverage)
        return ProjectGovernanceProjection(
            projectId: status.projectId, revision: status.policy.revision,
            enforcement: status.policy.enforcement, rules: summaries(status.policy.rules),
            coverage: rows, updatedAt: max(current.updatedAt, status.generatedAt),
            requiredCapabilities: status.coverage.requiredCapabilities,
            strictReady: strictReady(
                status.policy.enforcement, required: status.coverage.requiredCapabilities,
                coverage: rows
            ), policy: status.policy
        )
    }

    static func merged(
        current: ProjectGovernanceProjection?, ack: ProjectPolicyAck
    ) -> ProjectGovernanceProjection? {
        guard ProjectGovernanceWireValidator.validAck(ack), let current,
              current.projectId == ack.projectId,
              ack.acknowledgement.policyRevision == current.revision else { return current }
        let replacement = coverageRows(ack.acknowledgement)
        let ids = Set(replacement.map(\.id))
        let rows = mergedCoverage(current.coverage.filter { !ids.contains($0.id) }, replacement)
        let required = current.requiredCapabilities ?? []
        return ProjectGovernanceProjection(
            projectId: current.projectId, revision: current.revision,
            enforcement: current.enforcement, rules: current.rules, coverage: rows,
            updatedAt: max(current.updatedAt, ack.acknowledgement.observedAt),
            requiredCapabilities: required,
            strictReady: strictReady(current.enforcement, required: required, coverage: rows),
            policy: current.policy
        )
    }

    /// One named capability governed apart from the rest of its kind.
    struct NamedRule: Hashable, Codable {
        let kind: ProjectCapabilityKind
        let name: String
    }

    /// The rule id a named override is written under.
    ///
    /// It carries the kind and the name so a later edit replaces that override
    /// rather than adding a second one beside it, and so a name shared by two
    /// kinds stays two separate decisions.
    static func namedRuleId(_ rule: NamedRule) -> String {
        "granttap-named-\(rule.kind.rawValue)-\(rule.name)"
    }

    static func updatedPolicy(
        current: ProjectPolicy?, projectId: String, enforcement: ProjectEnforcementMode,
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect],
        named: [NamedRule: ProjectPolicyEffect] = [:], createdBy: String
    ) -> ProjectPolicy {
        let revision = (current?.revision ?? 0) + 1
        var rules = current?.rules.filter {
            !$0.ruleId.hasPrefix("granttap-default-") && !$0.ruleId.hasPrefix("granttap-named-")
        } ?? []
        rules += defaults.map { kind, effect in
            ProjectPolicyRule(
                ruleId: "granttap-default-\(kind.rawValue)", projectId: projectId,
                selector: ProjectPolicySelector(kind: kind), effect: effect,
                conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                revision: revision, createdBy: createdBy
            )
        }
        // A named rule is narrower than its kind's default, so forbidding one
        // server does not require forbidding every server.
        rules += named.map { target, effect in
            ProjectPolicyRule(
                ruleId: namedRuleId(target), projectId: projectId,
                selector: ProjectPolicySelector(kind: target.kind, displayName: target.name),
                effect: effect,
                conditions: ProjectPolicyConditions(endpointIds: [], providers: []),
                revision: revision, createdBy: createdBy
            )
        }
        rules = rules.map { rule in
            ProjectPolicyRule(
                ruleId: rule.ruleId, projectId: projectId, selector: rule.selector,
                effect: rule.effect, conditions: rule.conditions, revision: revision,
                createdBy: rule.createdBy
            )
        }.sorted { $0.ruleId < $1.ruleId }
        return ProjectPolicy(
            projectId: projectId, revision: revision, enforcement: enforcement, rules: rules,
            execution: current?.execution,
            restrictions: current?.restrictions.map {
                var next = $0
                next.revision = min($0.revision, revision)
                return next
            },
            environment: current?.environment.map {
                var next = $0
                next.revision = min($0.revision, revision)
                return next
            }
        )
    }

    /// The named overrides a policy already carries, for the editor to show.
    static func namedEffects(_ policy: ProjectPolicy?) -> [NamedRule: ProjectPolicyEffect] {
        var result: [NamedRule: ProjectPolicyEffect] = [:]
        for rule in policy?.rules ?? [] where rule.ruleId.hasPrefix("granttap-named-") {
            guard let kind = rule.selector.kind, let name = rule.selector.displayName else {
                continue
            }
            result[NamedRule(kind: kind, name: name)] = rule.effect
        }
        return result
    }

    static func defaultEffects(_ policy: ProjectPolicy?) -> [ProjectCapabilityKind: ProjectPolicyEffect] {
        var result: [ProjectCapabilityKind: ProjectPolicyEffect] = [:]
        for rule in policy?.rules ?? [] where rule.ruleId.hasPrefix("granttap-default-") {
            if let kind = rule.selector.kind { result[kind] = rule.effect }
        }
        return result
    }

    private static func projection(_ status: ProjectPolicyStatus) -> ProjectGovernanceProjection {
        let rows = status.coverage.endpoints.flatMap(coverageRows)
        return ProjectGovernanceProjection(
            projectId: status.projectId, revision: status.policy.revision,
            enforcement: status.policy.enforcement, rules: summaries(status.policy.rules),
            coverage: rows, updatedAt: status.generatedAt,
            requiredCapabilities: status.coverage.requiredCapabilities,
            strictReady: strictReady(
                status.policy.enforcement, required: status.coverage.requiredCapabilities,
                coverage: rows
            ), policy: status.policy
        )
    }

    private static func summaries(_ rules: [ProjectPolicyRule]) -> [ProjectPolicyRuleSummary] {
        rules.map { rule in
            let fingerprint = rule.selector.fingerprint
            return ProjectPolicyRuleSummary(
                ruleId: rule.ruleId, effect: rule.effect,
                capabilityKind: rule.selector.kind?.rawValue ?? "agent",
                displayName: rule.selector.displayName, provider: rule.selector.provider,
                origin: rule.selector.origin,
                fingerprintConfidence: fingerprint?.value?.rawValue
                    ?? fingerprint?.expected?.confidence.rawValue
            )
        }.sorted { $0.ruleId < $1.ruleId }
    }

    private static func coverageRows(
        _ ack: ProjectPolicyAcknowledgement
    ) -> [ProjectPolicyCoverageSummary] {
        ack.capabilities.map {
            ProjectPolicyCoverageSummary(
                endpointId: ack.endpointId, provider: ack.provider,
                capability: $0.kind.rawValue, status: $0.status,
                policyRevision: ack.policyRevision
            )
        }
    }

    private static func mergedCoverage(
        _ current: [ProjectPolicyCoverageSummary], _ incoming: [ProjectPolicyCoverageSummary]
    ) -> [ProjectPolicyCoverageSummary] {
        var values = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for row in incoming { values[row.id] = row }
        return values.values.sorted { $0.id < $1.id }
    }

    private static func strictReady(
        _ mode: ProjectEnforcementMode, required: [ProjectCapabilityKind],
        coverage: [ProjectPolicyCoverageSummary]
    ) -> Bool {
        guard mode == .strict, !required.isEmpty else { return true }
        let groups = Dictionary(grouping: coverage) { "\($0.endpointId)\u{1f}\($0.provider)" }
        guard !groups.isEmpty else { return false }
        return groups.values.allSatisfy { rows in
            required.allSatisfy { kind in
                rows.contains { $0.capability == kind.rawValue && $0.status == .enforced }
            }
        }
    }
}
