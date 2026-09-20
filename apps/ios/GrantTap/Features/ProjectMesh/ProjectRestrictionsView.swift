import SwiftUI

/// Project quality gates: the same rules CI reads from `.granttap/restrictions.json`.
struct ProjectRestrictionsView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var scope: ProjectRestrictionScope
    @State private var rules: [ProjectRestrictionRule]
    @State private var customSheet = false

    init(snapshot: ProjectMeshSnapshot, model: AppModel) {
        self.snapshot = snapshot
        self.model = model
        let current = snapshot.restrictions
            ?? model.projectGovernance[snapshot.projectId]?.policy?.restrictions
        _scope = State(initialValue: current?.scope ?? .project)
        _rules = State(initialValue: current?.rules ?? [])
    }

    var body: some View {
        List {
            Section {
                Picker(L("Apply to"), selection: $scope) {
                    Text(L("This Project")).tag(ProjectRestrictionScope.project)
                    Text(L("Project and repository")).tag(ProjectRestrictionScope.projectAndRepo)
                    Text(L("Sync from repository")).tag(ProjectRestrictionScope.syncFromRepo)
                }
                .disabled(model.demoMode)
            } footer: {
                Text(scopeFooter)
            }
            Section {
                ForEach(ProjectRestrictionsPresentation.recommended) { preset in
                    Toggle(isOn: recommendedBinding(preset)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ProjectRestrictionsPresentation.kindLabel(preset.kind))
                            Text(ProjectRestrictionsPresentation.ruleDetail(preset))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .disabled(model.demoMode || scope == .syncFromRepo)
                    .accessibilityIdentifier("project.restrictions.\(preset.ruleId)")
                }
                Button(String(format: L("Custom · %d rules"), customRules.count)) { customSheet = true }
                    .disabled(model.demoMode || scope == .syncFromRepo)
                    .accessibilityIdentifier("project.restrictions.custom")
                Button(L("Save restrictions")) {
                    _ = model.applyProjectRestrictions(
                        projectId: snapshot.projectId,
                        restrictions: ProjectRestrictionSet(
                            projectId: snapshot.projectId,
                            revision: 1,
                            scope: scope,
                            repositoryId: snapshot.project.canonicalRepositoryId,
                            rules: rules,
                            source: scope == .syncFromRepo ? "repo" : "phone"
                        )
                    )
                }
                .disabled(model.demoMode)
                .accessibilityIdentifier("project.restrictions.save")
            } header: {
                Text(L("Recommended"))
            } footer: {
                Text(statusDetail)
            }
        }
        .navigationTitle(L("Restrictions"))
        .sheet(isPresented: $customSheet) {
            ProjectRestrictionsCustomSheet(rules: $rules, enabled: !model.demoMode && scope != .syncFromRepo)
        }
    }

    var customRules: [ProjectRestrictionRule] {
        rules.filter { rule in
            !ProjectRestrictionsPresentation.recommended.contains { $0.ruleId == rule.ruleId }
        }
    }

    var scopeFooter: String {
        switch scope {
        case .project:
            return L("Hooks on this Project enforce the rules. CI is unchanged.")
        case .projectAndRepo:
            return L("The same rules are written to .granttap/restrictions.json for CI.")
        case .syncFromRepo:
            return L("The computer reads .granttap/restrictions.json and follows that file.")
        }
    }

    var statusDetail: String {
        if let error = model.projectPolicyErrors[snapshot.projectId] { return error }
        return ProjectRestrictionsPresentation.summary(
            snapshot, governance: model.projectGovernance[snapshot.projectId]
        )
    }

    private func recommendedBinding(_ preset: ProjectRestrictionRule) -> Binding<Bool> {
        Binding(
            get: { rules.contains { $0.ruleId == preset.ruleId } },
            set: { on in
                rules.removeAll { $0.ruleId == preset.ruleId }
                if on { rules.append(preset) }
            }
        )
    }
}

struct ProjectRestrictionsCustomSheet: View {
    @Binding var rules: [ProjectRestrictionRule]
    let enabled: Bool
    @State private var name = ""
    @State private var limit = "100"
    @State private var kind: ProjectRestrictionKind = .custom
    @Environment(\.dismiss) private var dismiss

    var extras: [ProjectRestrictionRule] {
        rules.filter { rule in
            !ProjectRestrictionsPresentation.recommended.contains { $0.ruleId == rule.ruleId }
        }
    }

    var body: some View {
        CompatNavigationStack {
            List {
                ForEach(extras) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.name ?? ProjectRestrictionsPresentation.kindLabel(rule.kind))
                            Text(ProjectRestrictionsPresentation.ruleDetail(rule))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            rules.removeAll { $0.ruleId == rule.ruleId }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(!enabled)
                    }
                }
                if enabled {
                    Picker(L("Kind"), selection: $kind) {
                        Text(L("Custom")).tag(ProjectRestrictionKind.custom)
                        Text(L("File line limit")).tag(ProjectRestrictionKind.maxFileLines)
                        Text(L("Method line limit")).tag(ProjectRestrictionKind.maxFunctionLines)
                    }
                    TextField(L("Name"), text: $name)
                    TextField(L("Limit"), text: $limit)
                        .keyboardType(.numberPad)
                    Button(L("Add rule")) {
                        let parsed = Int(limit)
                        let rule = ProjectRestrictionRule(
                            ruleId: "custom-\(UUID().uuidString.lowercased().prefix(8))",
                            kind: kind,
                            limit: kind == .custom ? parsed : (parsed ?? 100),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines),
                            effect: .deny
                        )
                        guard kind != .custom || rule.name != nil else { return }
                        rules.append(rule)
                        name = ""
                    }
                    .disabled(kind == .custom && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(L("Custom"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}
