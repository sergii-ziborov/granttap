import SwiftUI

struct ProjectRestrictionsView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var scope: String
    @State private var rules: [ProjectRestrictionRule]
    @State private var editing: ProjectRestrictionRule?

    private static let recommended = [
        ProjectRestrictionRule(ruleId: "max-file-lines", kind: "max_file_lines", limit: 300,
                               name: "File line limit", effect: "deny"),
        ProjectRestrictionRule(ruleId: "max-function-lines", kind: "max_function_lines", limit: 100,
                               name: "Function line limit", effect: "deny"),
        ProjectRestrictionRule(ruleId: "max-file-bytes", kind: "max_file_bytes", limit: 65_536,
                               name: "File size limit", effect: "ask"),
    ]

    init(snapshot: ProjectMeshSnapshot, model: AppModel) {
        self.snapshot = snapshot
        self.model = model
        let current = snapshot.restrictions
            ?? model.projectGovernance[snapshot.projectId]?.policy?.restrictions
        _scope = State(initialValue: current?.scope ?? "project")
        _rules = State(initialValue: current?.rules ?? [])
    }

    var body: some View {
        List {
            Section {
                Picker(L("Apply to"), selection: $scope) {
                    Text(L("This Mesh")).tag("project")
                    Text(L("Mesh and repository")).tag("project_and_repo")
                    Text(L("Sync from repository")).tag("sync_from_repo")
                }
            } footer: { Text(scopeHelp) }
            Section(L("Recommended")) {
                ForEach(Self.recommended) { preset in
                    HStack(spacing: 12) {
                        Button {
                            editing = rules.first { $0.ruleId == preset.ruleId } ?? preset
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name ?? preset.kind)
                                Text(ruleDetail(rules.first { $0.ruleId == preset.ruleId } ?? preset))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Toggle(preset.name ?? preset.kind, isOn: ruleBinding(preset))
                            .labelsHidden()
                    }
                    .disabled(scope == "sync_from_repo")
                }
            }
            Section(L("Custom rules")) {
                ForEach(customRules) { rule in
                    Button {
                        editing = rule
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.name ?? rule.kind)
                                Text(ruleDetail(rule)).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(scope == "sync_from_repo")
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { customRules[$0].ruleId })
                    rules.removeAll { ids.contains($0.ruleId) }
                }
                if scope != "sync_from_repo" {
                    Button {
                        editing = ProjectRestrictionRule(
                            ruleId: "rule-\(UUID().uuidString.lowercased())",
                            kind: "max_file_lines", limit: 300, effect: "ask"
                        )
                    } label: {
                        Label(L("Add rule"), systemImage: "plus")
                    }
                    .disabled(rules.count >= 32)
                }
            }
            Section {
                Button(L("Save restrictions")) {
                    _ = model.applyProjectRestrictions(
                        projectId: snapshot.projectId, scope: scope,
                        rules: scope == "sync_from_repo" ? [] : rules
                    )
                }
                .disabled(model.projectGovernance[snapshot.projectId] == nil
                          || (scope != "sync_from_repo" && rules.contains { $0.kind == "custom" }))
            } footer: { Text(status) }
        }
        .pageNavigationTitle(L("Restrictions"))
        .sheet(item: $editing) { rule in
            ProjectRestrictionRuleEditor(rule: rule,
                                         lockedKind: Self.recommended.contains { $0.ruleId == rule.ruleId }) {
                updated in
                rules.removeAll { $0.ruleId == updated.ruleId }
                rules.append(updated)
            }
        }
    }

    private var customRules: [ProjectRestrictionRule] {
        rules.filter { rule in !Self.recommended.contains { $0.ruleId == rule.ruleId } }
    }

    private var scopeHelp: String {
        switch scope {
        case "project_and_repo": return L("Agent hooks enforce these rules; the linked repository can share them with CI.")
        case "sync_from_repo": return L("The computer reads the repository's GrantTap restrictions.")
        default: return L("Mesh executions enforce these rules; CI is unchanged.")
        }
    }

    private var status: String {
        if scope != "sync_from_repo", rules.contains(where: { $0.kind == "custom" }) {
            return L("A legacy named rule has no computer check. Edit it to select a measurable check or delete it before saving.")
        }
        return model.projectPolicyErrors[snapshot.projectId]
            ?? L("Desired restrictions are applied only after endpoint acknowledgement.")
    }

    private func ruleBinding(_ preset: ProjectRestrictionRule) -> Binding<Bool> {
        Binding(
            get: { rules.contains { $0.ruleId == preset.ruleId } },
            set: { enabled in
                rules.removeAll { $0.ruleId == preset.ruleId }
                if enabled { rules.append(preset) }
            }
        )
    }

    private func ruleDetail(_ rule: ProjectRestrictionRule) -> String {
        if rule.kind == "custom" { return L("Unsupported legacy rule · edit to select a measurable check") }
        let paths = (rule.paths ?? []).isEmpty ? L("all files") : (rule.paths ?? []).joined(separator: ", ")
        return [rule.limit.map(String.init), rule.effect.uppercased(), paths]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
