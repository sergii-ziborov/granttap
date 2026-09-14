import SwiftUI

enum ProjectGovernancePresentation {
    static func effectLabel(_ effect: ProjectPolicyEffect) -> String {
        switch effect {
        case .allow: return L("Allow")
        case .ask: return L("Ask")
        case .deny: return L("Deny")
        }
    }

    static func coverageLabel(_ status: ProjectPolicyCoverageStatus) -> String {
        switch status {
        case .enforced: return L("Enforced")
        case .observed: return L("Observed only")
        case .unsupported: return L("Unsupported")
        case .unknown: return L("Unknown")
        }
    }

    static func enforcementLabel(_ mode: ProjectEnforcementMode) -> String {
        mode == .strict ? L("Strict") : L("Best available")
    }

    static func ruleTitle(_ rule: ProjectPolicyRuleSummary) -> String {
        rule.displayName ?? capabilityName(rule.capabilityKind)
    }

    static func ruleDetail(_ rule: ProjectPolicyRuleSummary) -> String? {
        let provider = rule.provider.map { AgentIdentity.displayName($0) }
        let confidence = rule.fingerprintConfidence.map { L($0.replacingOccurrences(
            of: "_", with: " "
        ).capitalized) }
        let values = [provider, rule.origin, confidence].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    static func coverageColor(_ status: ProjectPolicyCoverageStatus) -> Color {
        switch status {
        case .enforced: return Theme.ok
        case .observed: return Theme.riskMed
        case .unsupported: return Theme.riskHigh
        case .unknown: return Theme.muted
        }
    }

    static func coverageExplanation(_ status: ProjectPolicyCoverageStatus) -> String {
        switch status {
        case .enforced: return L("The provider's hook stops a call the policy denies and asks about one it questions, before it runs.")
        case .observed: return L("The provider reports the call after the fact; GrantTap sees it but cannot stop it.")
        case .unsupported: return L("The provider offers no hook for this kind on that computer; the policy cannot reach it.")
        case .unknown: return L("The computer has not said yet, or its hook is not installed.")
        }
    }

    /// "Enforced 14 · Observed 1 · Unsupported 9": only the counts that are there.
    static func coverageSummary(_ rows: [ProjectPolicyCoverageSummary]) -> String {
        guard !rows.isEmpty else { return L("No coverage reported yet.") }
        let parts: [String] = [ProjectPolicyCoverageStatus.enforced, .observed, .unsupported, .unknown].compactMap { status in
            let count = rows.filter { $0.status == status }.count
            return count > 0 ? "\(coverageLabel(status)) \(count)" : nil
        }
        return parts.joined(separator: " · ")
    }

    /// "Best available · revision 2", the one line the folded section shows.
    static func enforcementSummary(_ governance: ProjectGovernanceProjection) -> String {
        String(format: L("%@ · revision %d"), enforcementLabel(governance.enforcement), governance.revision)
    }

    static func capabilityName(_ value: String) -> String {
        switch value.lowercased() {
        case "mcp": return "MCP"
        case "cli": return "CLI"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
