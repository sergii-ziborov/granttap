import SwiftUI

/// Edits only checks that the computer actually evaluates for file writes.
struct ProjectRestrictionRuleEditor: View {
    let rule: ProjectRestrictionRule
    let lockedKind: Bool
    let onSave: (ProjectRestrictionRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var name: String
    @State private var limit: String
    @State private var effect: String
    @State private var paths: String

    init(rule: ProjectRestrictionRule, lockedKind: Bool, onSave: @escaping (ProjectRestrictionRule) -> Void) {
        self.rule = rule
        self.lockedKind = lockedKind
        self.onSave = onSave
        _kind = State(initialValue: rule.kind)
        _name = State(initialValue: rule.name ?? "")
        _limit = State(initialValue: rule.limit.map(String.init) ?? "")
        _effect = State(initialValue: rule.effect)
        _paths = State(initialValue: (rule.paths ?? []).joined(separator: "\n"))
    }

    private var draft: ProjectRestrictionRule? {
        Self.makeRule(from: rule, kind: kind, name: name, limit: limit,
                      effect: effect, paths: paths, requiresName: !lockedKind)
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    if !lockedKind {
                        Picker(L("Check"), selection: $kind) {
                            if kind == "custom" { Text(L("Select a supported check")).tag("custom") }
                            Text(L("File line limit")).tag("max_file_lines")
                            Text(L("Function line limit")).tag("max_function_lines")
                            Text(L("File size in bytes")).tag("max_file_bytes")
                        }
                    } else {
                        CompatLabeledContent(L("Check"), value: checkName(kind))
                    }
                    TextField(L("Rule name"), text: $name)
                    TextField(L("Maximum"), text: $limit).keyboardType(.numberPad)
                    Picker(L("When exceeded"), selection: $effect) {
                        Text(L("Ask")).tag("ask")
                        Text(L("Deny")).tag("deny")
                    }
                } footer: {
                    Text(L("The computer checks the changed file. A custom name alone cannot enforce a restriction."))
                }
                Section {
                    TextEditor(text: $paths)
                        .frame(minHeight: 90)
                        .accessibilityIdentifier("restrictions.paths")
                } header: {
                    Text(L("File paths · optional"))
                } footer: {
                    Text(L("One relative path or glob per line; leave empty for all files. Up to 16 paths."))
                }
                if draft == nil {
                    Section {
                        Text(L("Choose a check, a positive maximum up to 1,000,000, and valid relative paths."))
                            .foregroundStyle(Theme.riskMed)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Restriction rule"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        guard let draft else { return }
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft == nil)
                    .accessibilityIdentifier("restrictions.rule.save")
                }
            }
        }
    }

    static func makeRule(
        from original: ProjectRestrictionRule, kind: String, name: String, limit: String,
        effect: String, paths: String, requiresName: Bool
    ) -> ProjectRestrictionRule? {
        guard ["max_file_lines", "max_function_lines", "max_file_bytes"].contains(kind),
              let maximum = Int(limit), (1...1_000_000).contains(maximum),
              ["ask", "deny"].contains(effect) else { return nil }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 100, !requiresName || !title.isEmpty else { return nil }
        let patterns = paths.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard patterns.count <= 16,
              patterns.allSatisfy({ $0.count <= 256 && !$0.hasPrefix("/")
                  && !$0.split(separator: "/").contains("..") && !$0.contains("\0") })
        else { return nil }
        return ProjectRestrictionRule(
            ruleId: original.ruleId, kind: kind, limit: maximum,
            name: title.isEmpty ? nil : title,
            paths: patterns.isEmpty ? nil : patterns, effect: effect
        )
    }

    private func checkName(_ kind: String) -> String {
        switch kind {
        case "max_file_lines": return L("File line limit")
        case "max_function_lines": return L("Function line limit")
        case "max_file_bytes": return L("File size in bytes")
        default: return L("Unsupported legacy rule")
        }
    }
}
