import SwiftUI

/// One kind's custom rules, on their own sheet.
///
/// Custom used to unfold its table inline under the picker, which made the
/// Governance screen as long as every command the Project had ever run. The
/// picker row now says "Custom · 3 rules" and the table opens over it, with
/// the same Done chrome as every other sheet.
struct ProjectGovernanceCustomSheet: View {
    let kind: ProjectCapabilityKind
    let candidates: [ProjectGovernanceLogic.NamedRule]
    var serverTitles: [String: String] = [:]
    @Binding var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]
    @Binding var defaults: [ProjectCapabilityKind: ProjectPolicyEffect]
    @Binding var customNames: Set<ProjectGovernanceLogic.NamedRule>
    let enabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CompatNavigationStack {
            List {
                ProjectGovernanceNamedSection(
                    candidates: candidates, serverTitles: serverTitles, named: $named,
                    enabled: enabled, customNames: $customNames,
                    customKinds: [kind], defaults: $defaults
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle(ProjectGovernanceTable.kindTitle(kind))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}
