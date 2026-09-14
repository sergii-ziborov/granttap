import SwiftUI

/// Capabilities as the Project governs them, reported inside a task.
///
/// Skills, MCP servers and the shell are decided by Project policy, so a task
/// must not offer its own switch for them beside it — two switches for one
/// permission is how a chat ends up disagreeing with its own Project. The task
/// reports what it will meet and routes to the one place that decides it.
struct ChatGovernedCapabilitySection: View {
    let rows: [ChatCapabilityRow]
    let snapshot: ProjectMeshSnapshot
    let projection: ProjectGovernanceProjection
    @ObservedObject var model: AppModel

    var body: some View {
        ForEach(ChatCapabilityRow.Kind.allCases, id: \.self) { kind in
            let group = ChatCapabilitySort.rank(rows.filter { $0.kind == kind })
            if !group.isEmpty {
                Section {
                    ForEach(group) { row in
                        GovernedCapabilityRow(row: row, effect: effect(for: kind))
                    }
                } header: {
                    Text(kind.title)
                } footer: {
                    if let effect = effect(for: kind) {
                        Text(footer(kind, effect))
                    }
                }
            }
        }
        Section {
            NavigationLink {
                ProjectGovernanceView(project: snapshot.project, model: model)
            } label: {
                Label(L("Governance"), systemImage: "checkmark.shield")
            }
        } footer: {
            Text(L("Skills, MCP and shell access are Project policy. Changing them here would only disagree with the Project."))
                .font(.system(size: 11))
        }
    }

    private func effect(for kind: ChatCapabilityRow.Kind) -> ProjectPolicyEffect? {
        ChatCapabilityGovernance.effect(for: kind, in: projection)
    }

    /// A shell row answers for scripts too, so the footer names both.
    private func footer(_ kind: ChatCapabilityRow.Kind, _ effect: ProjectPolicyEffect) -> String {
        let governed = ChatCapabilityGovernance.governing(kind).count > 1
            ? L("Shell and scripts") : kind.title
        return String(
            format: L("%@ · Project policy says %@"),
            governed, ProjectGovernancePresentation.effectLabel(effect)
        )
    }
}

struct GovernedCapabilityRow: View {
    let row: ChatCapabilityRow
    let effect: ProjectPolicyEffect?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.kind.systemImage)
                .frame(width: 22).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).foregroundStyle(Theme.ink)
                if let usage = row.usage {
                    Text(usage).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            if let effect {
                Text(ProjectGovernancePresentation.effectLabel(effect))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(effect))
            } else {
                // The Project reports a policy but says nothing about this kind.
                Text(L("Inherit")).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(_ effect: ProjectPolicyEffect) -> Color {
        switch effect {
        case .allow: return Theme.ok
        case .ask: return Theme.riskMed
        case .deny: return Theme.riskHigh
        }
    }
}
