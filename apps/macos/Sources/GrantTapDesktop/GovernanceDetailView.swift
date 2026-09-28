import DesktopInspectorCore
import SwiftUI

struct GovernanceDetailView: View {
    let snapshot: InspectorSnapshot?

    var body: some View {
        if let policy = snapshot?.policy {
            List {
                Section("Project policy") {
                    LabeledContent("Revision", value: String(policy.revision))
                    LabeledContent("Mode", value: policy.enforcement)
                    if policy.rules.isEmpty {
                        Text("No Project rules").foregroundStyle(.secondary)
                    } else {
                        ForEach(policy.rules) { rule in
                            LabeledContent(rule.rule_id, value: rule.effect)
                        }
                    }
                }
                Section("Endpoint coverage") {
                    if let coverage = snapshot?.coverage {
                        coverageRows(coverage)
                    } else {
                        Text("Coverage unavailable or not at this policy revision.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ContentUnavailableView("No Project policy", systemImage: "checkmark.shield")
        }
    }

    @ViewBuilder private func coverageRows(_ coverage: InspectorPolicyCoverage) -> some View {
        Text("Endpoint receipts report enforcement; they do not independently verify it.")
            .font(.caption).foregroundStyle(.secondary)
        if coverage.required_capabilities.isEmpty {
            Text(coverage.policy_revision == 0
                 ? "No Project capability policy has been applied."
                 : "No capability enforcement required by this policy.")
        } else {
            LabeledContent("Required", value: coverage.required_capabilities
                .map(\.label).joined(separator: ", "))
            Text(coverage.strict_ready
                 ? "Current receipts report all required capabilities enforced."
                 : "Required capability coverage is incomplete or unreported.")
        }
        if coverage.endpoints.isEmpty {
            Text("No current endpoint receipts.").foregroundStyle(.secondary)
        } else {
            ForEach(coverage.endpoints) { endpoint in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(endpoint.endpoint_id) · \(endpoint.provider)").font(.headline)
                    Text("Policy revision \(endpoint.policy_revision) · Unix time \(endpoint.observed_at)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    ForEach(coverage.required_capabilities, id: \.self) { kind in
                        let status = endpoint.capabilities.first { $0.kind == kind }?.status
                        LabeledContent(kind.label, value: status?.label ?? "Unknown")
                    }
                }
            }
        }
    }
}
