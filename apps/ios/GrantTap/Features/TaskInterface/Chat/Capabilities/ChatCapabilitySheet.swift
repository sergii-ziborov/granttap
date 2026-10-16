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
    private let onClose: (() -> Void)?
    @State private var showHandoff = false

    init(
        sessionId: String, session: SessionInfo, rows: [ChatCapabilityRow],
        accent: Color, model: AppModel? = nil,
        onClose: (() -> Void)? = nil,
        onToggle: @escaping (ChatCapabilityRow) -> Void
    ) {
        self.sessionId = sessionId
        self.session = session
        self.rows = rows
        self.accent = accent
        modelOverride = model
        self.onClose = onClose
        self.onToggle = onToggle
    }

    private var model: AppModel { modelOverride ?? environmentModel }
    private var ranked: [ChatCapabilityRow] { ChatCapabilitySort.rank(rows) }
    private var route: ChatComputerRoute? { model.chatComputerRoute(forSessionId: sessionId) }
    var body: some View {
        ChatSheetNavigation(title: L("Task controls"), doneIdentifier: "chat.controls.done",
            onClose: { if let onClose { onClose() } else { dismiss() } }) {
            List {
                approvalSection
                if AgentIdentity.normalize(session.agent) == "codex" { accessSection }
                modelSection
                toolsSections
                taskHistorySection
                projectMeshSection
                taskInfoSection
            }
        }
        .sheet(isPresented: $showHandoff) {
            TaskHandoffSheet(session: session, model: model)
        }
    }

    private var approvalSection: some View {
        ChatApprovalSection(sessionId: sessionId, session: session, model: model)
    }

    private var accessSection: some View {
        ChatApprovalAccessSection(sessionId: sessionId, session: session, model: model)
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
                    Text(L("This Task is not linked to a Mesh yet, so its rules cannot be changed here."))
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
        if model.canOfferTaskTransfer(for: session) {
            Section(L("Mesh")) {
                Button(action: beginHandoff) {
                    Label(L("Transfer to…"), systemImage: "arrow.right.arrow.left")
                }
                .accessibilityIdentifier("chat.controls.transfer")
                Text(L("The same Task continues with another agent here, or on another computer of the chat. The target uses its own branch/worktree."))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    func beginHandoff() {
        showHandoff = true
    }

    var approvalBinding: Binding<PersonalApprovalMode> {
        ChatApprovalPreferences(sessionId: sessionId, session: session, model: model).binding
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
