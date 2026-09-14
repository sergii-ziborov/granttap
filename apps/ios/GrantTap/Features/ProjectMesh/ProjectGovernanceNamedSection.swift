import SwiftUI

/// Forbidding one server without forbidding every server.
///
/// A kind-wide default answers "may this Project use MCP at all", which is the
/// blunt question. The one actually asked in practice is narrower — this server,
/// that skill, `rm` but not `git` — and answering it by denying the whole kind
/// costs everything else the Project legitimately uses. So a kind set to
/// Custom gets a table: every named thing the Project touches is a row with
/// three cells — Allow, Ask, Deny — and "everything else" is the row that
/// says what happens to the rest.
struct ProjectGovernanceNamedSection: View {
    let candidates: [ProjectGovernanceLogic.NamedRule]
    /// Names servers report about themselves, when the phone has seen them.
    var serverTitles: [String: String] = [:]
    @Binding var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]
    let enabled: Bool
    /// Rows the person typed in, kept for the screen's life so a rule can be
    /// written for something the Project has not run yet.
    var customNames: Binding<Set<ProjectGovernanceLogic.NamedRule>>? = nil
    /// Only these kinds get a table. Nil shows every kind that has a row.
    var customKinds: Set<ProjectCapabilityKind>? = nil
    /// The kind's default, shown as the "everything else" row of its table.
    var defaults: Binding<[ProjectCapabilityKind: ProjectPolicyEffect]>? = nil

    @State private var drafts: [ProjectCapabilityKind: String] = [:]

    private var kinds: [ProjectCapabilityKind] {
        ProjectCapabilityKind.allCases.filter { kind in
            if let customKinds { return customKinds.contains(kind) }
            return customNames != nil || candidates.contains { $0.kind == kind }
        }
    }

    var body: some View {
        ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
            section(kind, last: index == kinds.count - 1)
        }
    }

    private func rows(_ kind: ProjectCapabilityKind) -> [ProjectGovernanceLogic.NamedRule] {
        candidates.filter { $0.kind == kind }
    }

    private func section(_ kind: ProjectCapabilityKind, last: Bool) -> some View {
        Section {
            if let defaults {
                everythingElseRow(kind, defaults: defaults)
            }
            ForEach(rows(kind), id: \.self) { candidate in
                row(candidate)
            }
            if let customNames {
                addRow(kind, into: customNames)
            }
        } header: {
            HStack(spacing: 0) {
                Text(customKinds == nil
                     ? ProjectGovernanceTable.kindTitle(kind)
                     : "\(ProjectGovernanceTable.kindTitle(kind)) · \(L("custom"))")
                Spacer()
                ForEach(ProjectPolicyEffect.allCases, id: \.self) { effect in
                    Text(ProjectGovernancePresentation.effectLabel(effect))
                        .frame(width: ProjectGovernanceTable.cellWidth)
                }
            }
        } footer: {
            if last {
                Text(L("Each row is one server, skill, command or tool of this Project. Allow, Ask or Deny applies to that row alone; a row with nothing chosen follows \"everything else\"."))
            }
        }
    }

    /// The kind's default, as a row: what happens to anything not named below.
    private func everythingElseRow(
        _ kind: ProjectCapabilityKind, defaults: Binding<[ProjectCapabilityKind: ProjectPolicyEffect]>
    ) -> some View {
        HStack(spacing: 0) {
            Text(L("Everything else"))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            ProjectGovernanceEffectCells(selected: defaults.wrappedValue[kind], enabled: enabled) { effect in
                let next = ProjectGovernanceTable.toggled(current: defaults.wrappedValue[kind], tapped: effect)
                if let next { defaults.wrappedValue[kind] = next } else { defaults.wrappedValue.removeValue(forKey: kind) }
            }
        }
        .accessibilityIdentifier("governance.rest.\(kind.rawValue)")
    }

    private func row(_ candidate: ProjectGovernanceLogic.NamedRule) -> some View {
        // A command keeps its typewriter face; a row that reads as a sentence
        // is set like one and may take a second line.
        let sentence = candidate.kind == .mcp || candidate.kind == .skill
            || ProjectGovernanceTable.rowLabel(candidate) != candidate.name
        return HStack(spacing: 0) {
            Text(label(candidate))
                .font(sentence ? .body : Theme.mono(14, .regular))
                .foregroundStyle(Theme.ink)
                .lineLimit(sentence ? 2 : 1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            ProjectGovernanceEffectCells(selected: named[candidate], enabled: enabled) { effect in
                let next = ProjectGovernanceTable.toggled(current: named[candidate], tapped: effect)
                if let next { named[candidate] = next } else { named.removeValue(forKey: candidate) }
            }
        }
        .accessibilityIdentifier("governance.row.\(candidate.kind.rawValue).\(candidate.name)")
    }

    private func addRow(
        _ kind: ProjectCapabilityKind, into customNames: Binding<Set<ProjectGovernanceLogic.NamedRule>>
    ) -> some View {
        HStack {
            TextField(ProjectGovernanceTable.placeholder(kind), text: draft(kind))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .disabled(!enabled)
            Button(L("Add")) {
                guard let rule = ProjectGovernanceTable.customRule(kind, name: drafts[kind] ?? "") else { return }
                customNames.wrappedValue.insert(rule)
                drafts[kind] = ""
            }
            .disabled(!enabled || ProjectGovernanceTable.customRule(kind, name: drafts[kind] ?? "") == nil)
            .accessibilityIdentifier("governance.add.\(kind.rawValue)")
        }
    }

    private func draft(_ kind: ProjectCapabilityKind) -> Binding<String> {
        Binding(get: { drafts[kind] ?? "" }, set: { drafts[kind] = $0 })
    }

    /// The label may read better than the id, but the rule still targets the id:
    /// two servers must never become indistinguishable to a policy.
    private func label(_ candidate: ProjectGovernanceLogic.NamedRule) -> String {
        if candidate.kind == .mcp,
           let title = serverTitles[candidate.name], !title.isEmpty {
            return title
        }
        return ProjectGovernanceTable.rowLabel(candidate)
    }
}
