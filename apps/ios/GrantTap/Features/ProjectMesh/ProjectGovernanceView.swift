import SwiftUI

struct ProjectGovernanceView: View {
    let project: ProjectMeshProject
    @ObservedObject var model: AppModel
    @State private var enforcement: ProjectEnforcementMode
    @State private var defaults: [ProjectCapabilityKind: ProjectPolicyEffect]
    @State private var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]
    /// Rows the person typed in, kept while the screen is open.
    @State private var customNames: Set<ProjectGovernanceLogic.NamedRule> = []
    /// Kinds whose table is open: every kind with a named rule, plus any the
    /// person set to Custom on this screen.
    @State private var customKinds: Set<ProjectCapabilityKind>
    /// Computed when the screen opens and when the policy or the typed rows
    /// change — not on every draw. Scanning the usage history on each draw is
    /// what made the table lag on every tap.
    @State private var candidates: [ProjectGovernanceLogic.NamedRule] = []
    /// The kind whose Custom table is open on a sheet.
    @State private var customSheetKind: ProjectCapabilityKind?
    @State private var toast: String?

    /// A started draft is injectable for the same reason the other sheets take
    /// one: a gate that only exists behind private state is a gate nothing can
    /// check, and this one decides whether a policy can be written at all.
    init(
        project: ProjectMeshProject,
        model: AppModel,
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect]? = nil
    ) {
        self.project = project
        self.model = model
        let governance = model.projectGovernance[project.projectId]
        // An edit in progress outranks the saved policy as the thing to show.
        // Reading the saved policy on every appearance is how someone's choices
        // were thrown away by walking back one screen.
        let draft = model.projectPolicyDrafts[project.projectId]
        _enforcement = State(
            initialValue: draft?.enforcement ?? governance?.enforcement ?? .bestAvailable
        )
        _defaults = State(
            initialValue: defaults ?? draft?.defaults
                ?? ProjectGovernanceLogic.defaultEffects(governance?.policy)
        )
        let named = draft?.named ?? ProjectGovernanceLogic.namedEffects(governance?.policy)
        _named = State(initialValue: named)
        _customKinds = State(initialValue: Set(named.keys.map(\.kind)))
    }

    var governance: ProjectGovernanceProjection? {
        model.projectGovernance[project.projectId]
    }

    var rules: [ProjectPolicyRuleSummary] {
        governance?.rules.sorted {
            $0.effect.severity == $1.effect.severity
                ? $0.ruleId < $1.ruleId : $0.effect.severity > $1.effect.severity
        } ?? []
    }

    var coverage: [ProjectPolicyCoverageSummary] {
        governance?.coverage.sorted {
            if $0.status.rank != $1.status.rank { return $0.status.rank < $1.status.rank }
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            return $0.capability < $1.capability
        } ?? []
    }

    var body: some View {
        List {
            if let governance {
                ProjectGovernanceEditorSection(
                    enforcement: $enforcement, defaults: $defaults,
                    // A reported Project can be edited, policy or not: the one
                    // with none is the one whose first policy has to be written.
                    enabled: !model.demoMode, customKinds: $customKinds, named: $named,
                    onCustom: { kind in customSheetKind = kind }
                )
                // One folded row instead of three sections: the rules list was
                // the pickers above said again, and coverage is detail.
                enforcementSection(governance)
            } else {
                Section {
                    CompatEmptyState(
                        title: L("Governance not reported"), systemImage: "checkmark.shield",
                        description: L("A linked computer has not reported Project policy yet.")
                    )
                }
            }
        }
        .navigationTitle(L("Governance"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Save")) { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear { refreshCandidates() }
        .onChange(of: governance?.revision) { _ in
            loadDraft()
            refreshCandidates()
        }
        .onChange(of: customNames) { _ in refreshCandidates() }
        .sheet(item: $customSheetKind) { kind in
            ProjectGovernanceCustomSheet(
                kind: kind, candidates: candidates, serverTitles: serverTitles,
                named: $named, defaults: $defaults, customNames: $customNames,
                enabled: !model.demoMode
            )
        }
        .transientToast($toast)
    }

    private func enforcementSection(_ governance: ProjectGovernanceProjection) -> some View {
        Section(L("Enforcement")) {
            NavigationLink {
                ProjectEnforcementDetailView(governance: governance, coverage: coverage)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ProjectGovernancePresentation.enforcementSummary(governance)).foregroundColor(Theme.ink)
                        if governance.enforcement == .strict {
                            Text(L(governance.strictReady == true ? "Ready" : "Incomplete"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(governance.strictReady == true ? Theme.ok : Theme.riskMed)
                        }
                    }
                    Text(ProjectGovernancePresentation.coverageSummary(coverage))
                        .font(.caption).foregroundColor(Theme.muted)
                }
            }
            .accessibilityIdentifier("governance.enforcement")
            if model.pendingProjectPolicyRevisions[project.projectId] != nil {
                Text(L("Sending…")).font(.caption).foregroundColor(Theme.riskMed)
            } else if let delivered = model.deliveredProjectPolicyRevisions[project.projectId] {
                // Saved means the relay has it, for every computer in the
                // Project, durably. Which computers have applied it is what
                // coverage below answers, and that is a different question.
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("Saved as revision %d"), delivered))
                        .font(.caption).foregroundColor(Theme.ok)
                    Text(L("Each computer applies it when it next reads the mesh. Coverage below says which have."))
                        .font(.caption2).foregroundColor(Theme.muted)
                }
            }
            if let error = model.projectPolicyErrors[project.projectId] {
                Text(error).font(.caption).foregroundColor(Theme.riskHigh)
            }
        }
    }

    /// Internal so the editor's one gate is asserted, not assumed.
    var canSave: Bool {
        // A Project with no policy yet is exactly the one that needs authoring,
        // and requiring a policy to already exist locked the editor shut in the
        // only case where it matters.
        guard let governance, !model.demoMode,
              model.pendingProjectPolicyRevisions[project.projectId] == nil else { return false }
        return enforcement != governance.enforcement
            || defaults != ProjectGovernanceLogic.defaultEffects(governance.policy)
            || named != ProjectGovernanceLogic.namedEffects(governance.policy)
    }

    private func save() {
        // Saying so once matters: the only other sign a tap worked was the
        // button going grey, which is also what a refused tap looks like.
        // "Saved" was a lie the phone told itself: the computer had not said a
        // word yet. Sent is what happened; the screen says when it is applied.
        toast = model.applyProjectGovernance(
            projectId: project.projectId, enforcement: enforcement,
            defaults: defaults, named: named
        )
            ? L("Sent to the Project's computers. This screen says when it is applied.")
            : model.projectPolicyErrors[project.projectId] ?? L("Policy could not be sent.")
    }

    private func loadDraft() {
        // Only when nothing is in flight. An edit waiting on the computers is
        // the state worth keeping, not the state worth overwriting.
        if let draft = model.projectPolicyDrafts[project.projectId] {
            enforcement = draft.enforcement
            defaults = draft.defaults
            named = draft.named
            customKinds = Set(draft.named.keys.map(\.kind))
            return
        }
        enforcement = governance?.enforcement ?? .bestAvailable
        defaults = ProjectGovernanceLogic.defaultEffects(governance?.policy)
        named = ProjectGovernanceLogic.namedEffects(governance?.policy)
        customKinds = Set(named.keys.map(\.kind))
    }

    private func refreshCandidates() {
        candidates = namedCandidates
    }

    /// The capabilities this Project has used, the tools every provider has,
    /// anything already decided, and anything typed in.
    private var namedCandidates: [ProjectGovernanceLogic.NamedRule] {
        ProjectGovernanceCandidates.named(
            events: CapabilityUsageStore.shared.events,
            sessionIds: projectSessionIds,
            existing: ProjectGovernanceLogic.namedEffects(governance?.policy),
            configured: configuredServers,
            extra: ProjectGovernanceCandidates.builtIn + Array(customNames)
        )
    }

    /// Servers the Project's chats are configured with, called or not.
    private var configuredServers: [String] {
        let ids = projectSessionIds
        var names = Set<String>()
        for session in model.sessions + model.allSessionHistory
        where ids.contains(session.sessionId) {
            for server in session.mcpServers ?? [] { names.insert(server.name) }
        }
        return names.sorted()
    }

    /// What each MCP server calls itself, from the sessions the phone knows.
    private var serverTitles: [String: String] {
        var titles: [String: String] = [:]
        for session in model.sessions + model.allSessionHistory {
            for server in session.mcpServers ?? [] where titles[server.name] == nil {
                titles[server.name] = server.displayTitle
            }
        }
        return titles
    }

    private var projectSessionIds: Set<String> {
        guard let snapshot = model.meshSnapshot(for: project.projectId) else { return [] }
        return Set(snapshot.executions.map(\.sessionId))
    }
}

struct ProjectPolicyRuleRow: View {
    let rule: ProjectPolicyRuleSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ProjectGovernancePresentation.ruleTitle(rule)).foregroundColor(Theme.ink)
                if let detail = ProjectGovernancePresentation.ruleDetail(rule) {
                    Text(detail).font(.caption).foregroundColor(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            Text(ProjectGovernancePresentation.effectLabel(rule.effect))
                .font(.caption.weight(.semibold)).foregroundColor(effectColor)
        }
        .padding(.vertical, 2)
    }

    private var effectColor: Color {
        switch rule.effect {
        case .allow: return Theme.ok
        case .ask: return Theme.riskMed
        case .deny: return Theme.riskHigh
        }
    }
}

struct ProjectPolicyCoverageRow: View {
    let item: ProjectPolicyCoverageSummary
    /// Off when the rows are already grouped under their computer.
    var showsEndpoint: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(AgentIdentity.displayName(item.provider)) · \(ProjectGovernancePresentation.capabilityName(item.capability))")
                if showsEndpoint {
                    Text(item.endpointId).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(ProjectGovernancePresentation.coverageLabel(item.status))
                .font(.caption.weight(.semibold)).foregroundColor(statusColor)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch item.status {
        case .enforced: return Theme.ok
        case .observed: return Theme.riskMed
        case .unsupported: return Theme.riskHigh
        case .unknown: return Theme.muted
        }
    }
}
