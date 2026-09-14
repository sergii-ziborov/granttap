import SwiftUI

/// What a kind's row can say: follow the computer, one answer for everything
/// of that kind, or Custom — a table below where each named thing gets its
/// own answer and "everything else" gets the default.
enum ProjectGovernanceChoice: Hashable {
    case inherit
    case effect(ProjectPolicyEffect)
    case custom

    static let all: [ProjectGovernanceChoice] = [.inherit, .effect(.allow), .effect(.ask), .effect(.deny), .custom]

    var label: String {
        switch self {
        case .inherit: return L("Inherit")
        case .effect(let effect): return ProjectGovernancePresentation.effectLabel(effect)
        case .custom: return L("Custom")
        }
    }

    static func current(
        kind: ProjectCapabilityKind,
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect],
        customKinds: Set<ProjectCapabilityKind>
    ) -> ProjectGovernanceChoice {
        if customKinds.contains(kind) { return .custom }
        return defaults[kind].map { .effect($0) } ?? .inherit
    }

    /// Applies a pick. Leaving Custom drops that kind's named rows: a rule
    /// that is no longer shown must not go on applying.
    static func apply(
        _ choice: ProjectGovernanceChoice, kind: ProjectCapabilityKind,
        defaults: inout [ProjectCapabilityKind: ProjectPolicyEffect],
        customKinds: inout Set<ProjectCapabilityKind>,
        named: inout [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]
    ) {
        switch choice {
        case .custom:
            customKinds.insert(kind)
        case .inherit:
            customKinds.remove(kind)
            defaults.removeValue(forKey: kind)
            named = named.filter { $0.key.kind != kind }
        case .effect(let effect):
            customKinds.remove(kind)
            defaults[kind] = effect
            named = named.filter { $0.key.kind != kind }
        }
    }
}

struct ProjectGovernanceEditorSection: View {
    @Binding var enforcement: ProjectEnforcementMode
    @Binding var defaults: [ProjectCapabilityKind: ProjectPolicyEffect]
    let enabled: Bool
    /// When given, each kind can also be Custom: the named table below then
    /// decides thing by thing. Without them the picker stays at four answers.
    var customKinds: Binding<Set<ProjectCapabilityKind>>? = nil
    var named: Binding<[ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]>? = nil
    /// Called when a kind is set to Custom, or its Custom row is tapped: the
    /// caller opens that kind's table.
    var onCustom: ((ProjectCapabilityKind) -> Void)? = nil

    private var choices: [ProjectGovernanceChoice] {
        customKinds == nil ? ProjectGovernanceChoice.all.filter { $0 != .custom } : ProjectGovernanceChoice.all
    }

    var body: some View {
        Section {
            Picker(L("Enforcement"), selection: $enforcement) {
                ForEach(ProjectEnforcementMode.allCases, id: \.self) { mode in
                    Text(ProjectGovernancePresentation.enforcementLabel(mode)).tag(mode)
                }
            }
            .disabled(!enabled)
            ForEach(ProjectCapabilityKind.allCases) { kind in
                Picker(Self.capabilityLabel(kind), selection: choiceBinding(kind)) {
                    ForEach(choices, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .disabled(!enabled)
                .accessibilityIdentifier("governance.kind.\(kind.rawValue)")
                if customKinds?.wrappedValue.contains(kind) == true {
                    Button {
                        onCustom?(kind)
                    } label: {
                        HStack {
                            Text(L("Custom rules")).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(Self.customSummary(kind, named: named?.wrappedValue ?? [:], defaults: defaults))
                                .foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        .font(.subheadline)
                    }
                    .disabled(!enabled)
                    .accessibilityIdentifier("governance.custom.\(kind.rawValue)")
                }
            }
        } header: {
            Text(L("Project policy"))
        } footer: {
            if customKinds != nil {
                Text(L("Custom opens a table for that kind: each server, command or tool gets its own answer, and everything else gets the default."))
            }
        }
    }

    private func choiceBinding(_ kind: ProjectCapabilityKind) -> Binding<ProjectGovernanceChoice> {
        Binding(
            get: {
                ProjectGovernanceChoice.current(
                    kind: kind, defaults: defaults, customKinds: customKinds?.wrappedValue ?? []
                )
            },
            set: { choice in
                var kinds = customKinds?.wrappedValue ?? []
                var rules = named?.wrappedValue ?? [:]
                ProjectGovernanceChoice.apply(
                    choice, kind: kind, defaults: &defaults, customKinds: &kinds, named: &rules
                )
                customKinds?.wrappedValue = kinds
                named?.wrappedValue = rules
                if choice == .custom { onCustom?(kind) }
            }
        )
    }

    /// "2 rules · everything else: Allow", for the row under a Custom kind.
    static func customSummary(
        _ kind: ProjectCapabilityKind,
        named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect],
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect]
    ) -> String {
        let rows = named.keys.filter { $0.kind == kind }.count
        let rest = defaults[kind].map(ProjectGovernancePresentation.effectLabel) ?? L("Inherit")
        return String(format: L(rows == 1 ? "%d rule" : "%d rules"), rows) + " · " + String(format: L("rest: %@"), rest)
    }

    static func capabilityLabel(_ kind: ProjectCapabilityKind) -> String {
        switch kind {
        case .agent: return L("Agents")
        case .mcp: return "MCP"
        case .skill: return L("Skills")
        case .shell: return L("Shell")
        case .script: return L("Scripts")
        case .fileWrite: return L("File writes")
        case .deploy: return L("Deploy")
        case .network: return L("Network")
        }
    }
}
