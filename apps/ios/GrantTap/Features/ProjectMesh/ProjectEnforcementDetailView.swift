import SwiftUI

/// What is actually in force, computer by computer.
///
/// The Governance screen says how the policy was written; this one says how
/// far it reaches: which computer enforces which kind for which provider,
/// which only watches, which cannot, and what each of those words means.
struct ProjectEnforcementDetailView: View {
    let governance: ProjectGovernanceProjection
    let coverage: [ProjectPolicyCoverageSummary]

    /// Rows by computer, each computer's rows by provider then capability.
    var byComputer: [(endpointId: String, rows: [ProjectPolicyCoverageSummary])] {
        Dictionary(grouping: coverage, by: \.endpointId)
            .map { key, rows in
                (endpointId: key, rows: rows.sorted {
                    if $0.provider != $1.provider { return $0.provider < $1.provider }
                    return $0.capability < $1.capability
                })
            }
            .sorted { $0.endpointId < $1.endpointId }
    }

    var body: some View {
        List {
            Section(L("Policy")) {
                CompatLabeledContent(
                    L("Mode"), value: ProjectGovernancePresentation.enforcementLabel(governance.enforcement)
                )
                CompatLabeledContent(L("Policy revision"), value: "\(governance.revision)")
                if governance.enforcement == .strict {
                    CompatLabeledContent(
                        L("Strict readiness"),
                        value: L(governance.strictReady == true ? "Ready" : "Incomplete")
                    )
                }
            }
            if coverage.isEmpty {
                Section {
                    Text(L("No enforcement coverage reported.")).foregroundColor(Theme.muted)
                }
            } else {
                ForEach(byComputer, id: \.endpointId) { computer in
                    Section {
                        ForEach(computer.rows) { item in ProjectPolicyCoverageRow(item: item, showsEndpoint: false) }
                    } header: {
                        Text(computer.endpointId)
                    } footer: {
                        Text(ProjectGovernancePresentation.coverageSummary(computer.rows))
                    }
                }
            }
            Section {
                ForEach([ProjectPolicyCoverageStatus.enforced, .observed, .unsupported, .unknown], id: \.self) { status in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ProjectGovernancePresentation.coverageLabel(status))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ProjectGovernancePresentation.coverageColor(status))
                        Text(ProjectGovernancePresentation.coverageExplanation(status))
                            .font(.caption).foregroundColor(Theme.muted)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(L("What each status means"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Enforcement"))
    }
}
