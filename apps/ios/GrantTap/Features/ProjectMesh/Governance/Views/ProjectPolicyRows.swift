import SwiftUI

struct ProjectPolicyRuleRow: View {
    let rule: ProjectPolicyRuleSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ProjectGovernancePresentation.ruleTitle(rule)).foregroundColor(Theme.ink)
                if let detail = ProjectGovernancePresentation.ruleDetail(rule) {
                    Text(detail).font(.caption).foregroundColor(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            Text(ProjectGovernancePresentation.effectLabel(rule.effect))
                .font(.caption.weight(.semibold)).foregroundColor(effectColor)
        }
        .padding(.vertical, 2)
    }

    private var effectColor: Color {
        switch rule.effect {
        case .allow: return Theme.ok
        case .ask: return Theme.riskMed
        case .deny: return Theme.riskHigh
        }
    }
}

struct ProjectPolicyCoverageRow: View {
    let item: ProjectPolicyCoverageSummary
    /// Off when the rows are already grouped under their computer.
    var showsEndpoint: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(AgentIdentity.displayName(item.provider)) · \(ProjectGovernancePresentation.capabilityName(item.capability))")
                if showsEndpoint {
                    Text(item.endpointId).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(ProjectGovernancePresentation.coverageLabel(item.status))
                .font(.caption.weight(.semibold)).foregroundColor(statusColor)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch item.status {
        case .enforced: return Theme.ok
        case .observed: return Theme.riskMed
        case .unsupported: return Theme.riskHigh
        case .unknown: return Theme.muted
        }
    }
}
