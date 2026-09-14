import SwiftUI

struct ProviderControlSupport {
    let mcp: Bool
    let skills: Bool
    let cli: Bool

    static func forAgent(_ agent: String) -> ProviderControlSupport {
        switch AgentIdentity.normalize(agent) {
        case "claude": return ProviderControlSupport(mcp: true, skills: true, cli: true)
        case "codex", "cursor": return ProviderControlSupport(mcp: true, skills: false, cli: true)
        case "grok": return ProviderControlSupport(mcp: true, skills: true, cli: true)
        default: return ProviderControlSupport(mcp: false, skills: false, cli: false)
        }
    }
}

enum PersonalApprovalMode: String, CaseIterable, Identifiable {
    case risky
    case every
    case defaults

    var id: String { rawValue }
    var label: String {
        switch self {
        case .risky: return L("Ask for risky actions")
        case .every: return L("Ask for every action")
        case .defaults: return L("Use agent defaults")
        }
    }
}

/// Secondary task controls. The task itself remains a chat/activity screen.
struct ChatCapabilitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environmentModel: AppModel
    let sessionId: String
    let session: SessionInfo
    let rows: [ChatCapabilityRow]
    let accent: Color
    let onToggle: (ChatCapabilityRow) -> Void
    private let modelOverride: AppModel?
    @State private var showHandoff = false

    init(
        sessionId: String, session: SessionInfo, rows: [ChatCapabilityRow],
        accent: Color, model: AppModel? = nil,
        onToggle: @escaping (ChatCapabilityRow) -> Void
    ) {
        self.sessionId = sessionId
        self.session = session
        self.rows = rows
        self.accent = accent
        modelOverride = model
        self.onToggle = onToggle
    }

    private var model: AppModel { modelOverride ?? environmentModel }
    private var ranked: [ChatCapabilityRow] { ChatCapabilitySort.rank(rows) }
    private var route: ChatComputerRoute? { model.chatComputerRoute(forSessionId: sessionId) }
    private var legacyLevel: String? {
        let level = model.autoAcceptLevel(for: sessionId)
        return ["safe", "except_destructive", "full"].contains(level) ? level : nil
    }

    var body: some View {
        CompatNavigationStack {
            List {
                approvalSection
                if AgentIdentity.normalize(session.agent) == "codex" { accessSection }
                modelSection
                toolsSections
                taskHistorySection
                projectMeshSection
                taskInfoSection
            }
            .navigationTitle(L("Task controls"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showHandoff) {
            TaskHandoffSheet(session: session, model: model)
        }
    }

    private var approvalSection: some View {
        Section(L("Approval Mode")) {
            Picker(L("Approval Mode"), selection: approvalBinding) {
                ForEach(PersonalApprovalMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
            Text(L("Ask for risky actions is recommended for most tasks."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            if let legacyLevel {
                CompatLabeledContent(L("Advanced · Custom")) {
                    Text(legacyLabel(legacyLevel)).foregroundStyle(Theme.riskMed)
                }
            }
        }
    }

    private var accessSection: some View {
        Section(L("Access")) {
            Picker(L("Codex access"), selection: accessBinding) {
                Text(L("Read only")).tag("read-only")
                Text(L("Workspace")).tag("workspace")
                Text(L("Full access")).tag("full")
            }
            Text(L("Applies to the next turn sent from GrantTap."))
                .font(.system(size: 11))
                .foregroundStyle(session.accessLevel == "full" ? Theme.riskHigh : Theme.muted)
        }
    }

    private var modelSection: some View {
        ChatTurnOverridesSection(sessionId: sessionId, agent: session.agent, model: model)
    }

    /// The Project that decides this chat's capabilities, once it reports one.
    private var governance: (ProjectMeshSnapshot, ProjectGovernanceProjection)? {
        guard let projectId = session.projectId,
              let snapshot = model.meshSnapshot(for: projectId),
              let projection = model.projectGovernance[projectId] else { return nil }
        return (snapshot, projection)
    }

    /// Capabilities are Project policy, so a task reports them and never offers
    /// a switch of its own — two switches for one permission is how a chat ends
    /// up disagreeing with its own Project. Where no Project governs the chat
    /// yet, the task says so and points at where the decision lives.
    @ViewBuilder private var toolsSections: some View {
        if let (snapshot, projection) = governance {
            ChatGovernedCapabilitySection(
                rows: rows, snapshot: snapshot, projection: projection, model: model
            )
        } else {
            ForEach(ChatCapabilityRow.Kind.allCases, id: \.self) { kind in
                let group = ranked.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { row in
                            GovernedCapabilityRow(row: row, effect: nil)
                        }
                    } header: {
                        Text(kind.title)
                    }
                }
            }
            if !rows.isEmpty {
                Section {
                    Text(L("No Project governs this task yet, so nothing here can be changed from the task."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var taskHistorySection: some View {
        Section {
            NavigationLink {
                TaskUsageHistoryView(
                    sessionIds: Set([
                        sessionId, session.sessionId,
                        model.resolvedSessionId(session.sessionId),
                    ])
                )
            } label: {
                Label(L("Task history"), systemImage: "chart.bar.doc.horizontal")
            }
        } footer: {
            Text(L("MCP, skills, shell and what each cost — for this task alone."))
                .font(.system(size: 11))
        }
    }

    private var taskInfoSection: some View {
        Section(L("Task Info")) {
            infoRow("Computer", route?.computerName ?? L("Unknown"))
            infoRow("Provider", AgentIdentity.displayName(session.agent))
            if let value = session.model { infoRow("Model", value) }
            if let value = session.cwd { infoRow("Folder", value) }
            if let value = session.branch, !value.isEmpty { infoRow("Branch", value) }
            infoRow("Session ID", session.sessionId)
            infoRow("Started", Date(timeIntervalSince1970: session.startedAt / 1000).formatted())
        }
    }

    @ViewBuilder var projectMeshSection: some View {
        if session.projectId != nil, session.taskId != nil,
           ["claude", "codex"].contains(AgentIdentity.normalize(session.agent)),
           !model.connectionRegistry.connections.isEmpty {
            Section("Project Mesh") {
                Button(action: beginHandoff) {
                    Label(L("Hand off task"), systemImage: "arrow.right.arrow.left")
                }
                Text(L("The same Task continues with another agent here, or on another computer of the Project. The target uses its own branch/worktree."))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    func beginHandoff() {
        showHandoff = true
    }

    var approvalBinding: Binding<PersonalApprovalMode> {
        Binding(get: {
            if model.isExcluded(sessionId) { return .defaults }
            return model.autoAcceptLevel(for: sessionId) == "ask" ? .every : .risky
        }, set: { mode in
            model.setAutoAcceptPaused(false)
            switch mode {
            case .defaults:
                model.setSessionExcluded(sessionId, true)
            case .every:
                model.setGating(true)
                model.setSessionAutoAccept(sessionId, "ask")
            case .risky:
                model.setGating(true)
                model.setSessionAutoAccept(sessionId, "except_push")
            }
        })
    }

    var accessBinding: Binding<String> {
        Binding(
            get: { session.accessLevel ?? "workspace" },
            set: { model.setSessionAccess(sessionId, $0) }
        )
    }


    func legacyLabel(_ level: String) -> String {
        switch level {
        case "safe": return L("Safe only")
        case "except_destructive": return L("Custom relaxed")
        default: return L("Full auto")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        CompatLabeledContent(L(label)) {
            Text(value).font(Theme.mono(11)).lineLimit(2).truncationMode(.middle)
        }
    }
}

struct ChatCapabilityRowView: View {
    let row: ChatCapabilityRow
    let accent: Color
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: row.kind.systemImage).foregroundStyle(Theme.muted)
                Text(row.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if row.needsAuth {
                    Text(L("sign in")).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.riskMed)
                } else if row.isControllable {
                    HStack(spacing: 6) {
                        Text(row.controlLabel ?? "")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Toggle("", isOn: Binding(
                            get: { row.allowed != false }, set: { _ in onToggle() }
                        ))
                        .labelsHidden()
                        .tint(Theme.ok)
                        .accessibilityValue(row.controlLabel ?? "")
                    }
                } else {
                    Text(L("Observed only")).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            Text(row.usage ?? L("Not observed in this task"))
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
    }
}
