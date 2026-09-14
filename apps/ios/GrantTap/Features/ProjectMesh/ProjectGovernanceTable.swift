import SwiftUI

/// Three cells, one chosen or none: the same shape on every row so a column
/// can be read top to bottom.
struct ProjectGovernanceEffectCells: View {
    let selected: ProjectPolicyEffect?
    let enabled: Bool
    let onTap: (ProjectPolicyEffect) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProjectPolicyEffect.allCases, id: \.self) { effect in
                Button {
                    onTap(effect)
                } label: {
                    Image(systemName: selected == effect ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(selected == effect ? ProjectGovernanceTable.color(effect) : Theme.line)
                        .frame(width: ProjectGovernanceTable.cellWidth, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityLabel(ProjectGovernancePresentation.effectLabel(effect))
                .accessibilityAddTraits(selected == effect ? .isSelected : [])
            }
        }
    }
}

enum ProjectGovernanceTable {
    static let cellWidth: CGFloat = 46

    /// The name the Mac gives a commit or PR that carries a co-author or
    /// "generated with" trailer. A Project that wants its history authored by
    /// people sets this row to Deny and leaves the rest of the shell alone.
    static let coAuthorship = "co-authorship"

    /// What a row is called on screen. A name the Mac coined for a kind of
    /// call reads as a sentence; a server or command keeps its own name.
    static func rowLabel(_ candidate: ProjectGovernanceLogic.NamedRule) -> String {
        if candidate.kind == .mcp { return MCPIdentity(name: candidate.name).displayName }
        if candidate.kind == .shell, candidate.name == coAuthorship {
            return L("Commit or PR with a co-author or generated-with trailer")
        }
        return candidate.name
    }

    /// Tapping the chosen cell clears it: back to following the kind.
    static func toggled(current: ProjectPolicyEffect?, tapped: ProjectPolicyEffect) -> ProjectPolicyEffect? {
        current == tapped ? nil : tapped
    }

    static func color(_ effect: ProjectPolicyEffect) -> Color {
        switch effect {
        case .allow: return Theme.ok
        case .ask: return Theme.riskMed
        case .deny: return Theme.riskHigh
        }
    }

    static func kindTitle(_ kind: ProjectCapabilityKind) -> String {
        switch kind {
        case .agent: return L("Agent tools")
        case .mcp: return L("MCP servers")
        case .skill: return L("Skills")
        case .shell: return L("Shell commands")
        case .script: return L("Scripts")
        case .fileWrite: return L("File writes")
        case .deploy: return L("Deploy")
        case .network: return L("Network")
        }
    }

    static func placeholder(_ kind: ProjectCapabilityKind) -> String {
        switch kind {
        case .agent: return L("Tool, e.g. Task")
        case .mcp: return L("Server name")
        case .skill: return L("Skill name")
        case .shell: return L("Command, e.g. rm")
        case .script: return L("Script file, e.g. deploy.sh")
        case .fileWrite: return L("Tool, e.g. Write")
        case .deploy: return L("Phrase, e.g. git push")
        case .network: return L("Command or tool, e.g. curl")
        }
    }

    /// A typed name becomes a row when it is a name: trimmed, one line, and
    /// no longer than the Mac accepts.
    static func customRule(_ kind: ProjectCapabilityKind, name: String) -> ProjectGovernanceLogic.NamedRule? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 160,
              clean.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return .init(kind: kind, name: clean)
    }
}

enum ProjectGovernanceCandidates {
    /// The names every provider fingerprints the same way, so a Project can
    /// decide about them before they have ever run here: the agent's own
    /// tools, and the phrases that make a shell call a deploy or a network
    /// call — "git push" is what a person means by "forbid pushing".
    static let builtIn: [ProjectGovernanceLogic.NamedRule] = [
        .init(kind: .agent, name: "Agent"), .init(kind: .agent, name: "Task"),
        .init(kind: .fileWrite, name: "Edit"), .init(kind: .fileWrite, name: "Write"),
        .init(kind: .fileWrite, name: "MultiEdit"), .init(kind: .fileWrite, name: "NotebookEdit"),
        .init(kind: .deploy, name: "git push"), .init(kind: .deploy, name: "npm publish"),
        .init(kind: .deploy, name: "deploy"), .init(kind: .deploy, name: "release"),
        .init(kind: .network, name: "curl"), .init(kind: .network, name: "wget"),
        .init(kind: .network, name: "ssh"), .init(kind: .network, name: "scp"), .init(kind: .network, name: "rsync"),
        .init(kind: .network, name: "WebFetch"), .init(kind: .network, name: "WebSearch"),
        .init(kind: .shell, name: "rm"), .init(kind: .shell, name: "sudo"),
        .init(kind: .shell, name: ProjectGovernanceTable.coAuthorship),
    ]

    /// What this Project has actually used, plus anything already decided.
    ///
    /// Offering every capability on the machine would bury the handful this
    /// Project touches; offering only what it used would hide a rule already
    /// written for something it has not run lately.
    static func named(
        events: [CapabilityUsageEvent],
        sessionIds: Set<String>,
        existing: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect],
        configured: [String] = [],
        extra: [ProjectGovernanceLogic.NamedRule] = []
    ) -> [ProjectGovernanceLogic.NamedRule] {
        var seen = Set(existing.keys)
        // A server this Project has configured can be forbidden before it is
        // ever called. Offering only what had already run meant the rule could
        // not be written until after the thing it forbids had done its work.
        for name in configured { seen.insert(.init(kind: .mcp, name: name)) }
        for event in events where event.sessionId.map(sessionIds.contains) == true {
            guard let kind = governedKind(event.kind, name: event.name) else { continue }
            seen.insert(.init(kind: kind, name: event.name))
        }
        for rule in extra { seen.insert(rule) }
        return seen.sorted {
            $0.kind.rawValue == $1.kind.rawValue
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.kind.rawValue < $1.kind.rawValue
        }
    }

    /// A shell call is governed as a script when it runs one, so a name that
    /// is a script file is offered under the kind the Mac fingerprints it as.
    static func governedKind(_ kind: CapabilityUsageKind, name: String) -> ProjectCapabilityKind? {
        switch kind {
        case .mcp: return .mcp
        case .skill: return .skill
        case .cli: return isScriptName(name) ? .script : .shell
        }
    }

    static func governedKind(_ kind: CapabilityUsageKind) -> ProjectCapabilityKind? {
        governedKind(kind, name: "")
    }

    static func isScriptName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".sh", ".bash", ".zsh", ".py", ".js", ".mjs", ".cjs", ".ts"].contains { lower.hasSuffix($0) }
    }
}
