import SwiftUI

struct ProjectGovernanceView: View {
    enum EditorMode { case governance, actionRules }
    let mode: EditorMode
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
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect]? = nil,
        mode: EditorMode = .governance
    ) {
        self.mode = mode
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

    var effectiveEnforcement: ProjectEnforcementMode {
        mode == .actionRules ? governance?.enforcement ?? enforcement : enforcement
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
            ProjectGovernanceEditorSection(
                enforcement: $enforcement, defaults: $defaults,
                enabled: !model.demoMode, showsEnforcement: mode == .governance,
                customKinds: $customKinds, named: $named,
                onCustom: { kind in customSheetKind = kind }
            )
            if let governance, mode == .governance { enforcementSection(governance) }
            deliverySection
        }
        .pageNavigationTitle(L(mode == .governance ? "Governance" : "Action rules"),
                             actionPlacement: .confirmationAction) {
            Button(L("Save")) { save() }
                .disabled(!canSave)
        }
        .onAppear { refreshCandidates() }
        .onChange(of: governance?.revision) { _ in
            loadDraft()
            refreshCandidates()
        }
        .onChange(of: customNames) { _ in refreshCandidates() }
        .onChange(of: defaults) { _ in rememberDraft() }
        .onChange(of: named) { _ in rememberDraft() }
        .onChange(of: enforcement) { _ in rememberDraft() }
        #if targetEnvironment(macCatalyst)
        .task(id: project.projectId) { await model.refreshLocalProjectPolicy(projectId: project.projectId) }
        #endif
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
        }
    }

    private var deliverySection: some View {
        Section {
            if model.pendingProjectPolicyRevisions[project.projectId] != nil {
                Text(L("Applying policy…")).foregroundStyle(Theme.muted)
            } else if let revision = governance?.revision, revision > 0 {
                CompatLabeledContent(L("Saved policy revision"), value: "\(revision)")
            } else if let delivered = model.deliveredProjectPolicyRevisions[project.projectId] {
                Text(String(format: L("Saved as revision %d"), delivered))
            }
            if let error = model.projectPolicyErrors[project.projectId] {
                Text(error).foregroundStyle(Theme.riskHigh)
                #if targetEnvironment(macCatalyst)
                Button(L("Retry")) {
                    Task { await model.refreshLocalProjectPolicy(projectId: project.projectId) }
                }
                #endif
            }
        }
    }

    private func rememberDraft() {
        let draft = ProjectGovernanceDraft(enforcement: effectiveEnforcement, defaults: defaults, named: named)
        if draft.differs(from: governance?.policy, enforcement: governance?.enforcement ?? .bestAvailable) {
            model.projectPolicyDrafts[project.projectId] = draft
        } else if model.pendingProjectPolicyRevisions[project.projectId] == nil {
            model.projectPolicyDrafts.removeValue(forKey: project.projectId)
        }
    }

    /// Internal so the editor's one gate is asserted, not assumed.
    var canSave: Bool {
        // A Project with no policy yet is exactly the one that needs authoring,
        // and requiring a policy to already exist locked the editor shut in the
        // only case where it matters.
        guard !model.demoMode,
              model.pendingProjectPolicyRevisions[project.projectId] == nil else { return false }
        return effectiveEnforcement != (governance?.enforcement ?? .bestAvailable)
            || defaults != ProjectGovernanceLogic.defaultEffects(governance?.policy)
            || named != ProjectGovernanceLogic.namedEffects(governance?.policy)
    }

    private func save() {
        // Saying so once matters: the only other sign a tap worked was the
        // button going grey, which is also what a refused tap looks like.
        // "Saved" was a lie the phone told itself: the computer had not said a
        // word yet. Sent is what happened; the screen says when it is applied.
        toast = model.applyProjectGovernance(
            projectId: project.projectId, enforcement: effectiveEnforcement,
            defaults: defaults, named: named
        )
            ? L("Applying Mesh policy. Confirmation will appear here.")
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

struct ProjectActionRulesView: View {
    let project: ProjectMeshProject
    @ObservedObject var model: AppModel

    var body: some View {
        ProjectGovernanceView(project: project, model: model, mode: .actionRules)
    }
}
