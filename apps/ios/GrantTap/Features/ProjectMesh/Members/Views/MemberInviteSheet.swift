import SwiftUI

/// Invite a person into a Project's mesh: who they are, what they may do,
/// then the one code their phone scans.
struct MemberInviteSheet: View {
    let projectId: String
    @ObservedObject var model: AppModel
    var parker: AppModel.MemberInviteParker? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: MemberRole = .member
    @State private var selectedAccountId = ""
    @State private var rules = MemberRules.preset(.member)
    @State private var lifetimeMinutes = 15
    @State private var selectedProjectIds: Set<String>
    @State private var invite: String
    @State private var error = ""
    @State private var creating = false
    @State private var showShare = false

    init(projectId: String, model: AppModel, parker: AppModel.MemberInviteParker? = nil,
         initialInvite: String = "", initialAccountId: String = "") {
        self.projectId = projectId
        self.model = model
        self.parker = parker
        _invite = State(initialValue: initialInvite)
        _selectedAccountId = State(initialValue: initialAccountId)
        _selectedProjectIds = State(initialValue: projectId.isEmpty ? [] : [projectId])
    }

    private var availableProjects: [ProjectMeshSnapshot] {
        model.meshSnapshots.values.filter {
            $0.projectId == projectId || !model.ownComputerRooms(for: $0.projectId).isEmpty
        }.sorted { $0.project.name < $1.project.name }
    }

    private var selectedAccount: CompanyAccount? {
        model.companyAccounts.first { $0.id == selectedAccountId }
    }

    private var accountCoversSelection: Bool {
        guard let account = selectedAccount, !account.disabled else { return false }
        return selectedProjectIds.allSatisfy { id in
            model.meshSnapshots[id].map { CompanyAccountPolicy.canReceive($0, account: account) } == true
        }
    }

    var body: some View {
        CompatNavigationStack {
            List {
                if invite.isEmpty {
                    Section {
                        TextField(L("Name"), text: $name)
                        Picker(L("Company account"), selection: $selectedAccountId) {
                            Text(L("Choose account")).tag("")
                            ForEach(model.companyAccounts.filter { !$0.disabled }) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        NavigationLink {
                            CompanyAccountsView(model: model)
                        } label: {
                            Text(L("Manage company accounts"))
                        }
                        if !projectId.isEmpty { Picker(L("Role"), selection: $role) {
                            ForEach(MemberRole.allCases) { role in Text(role.title).tag(role) }
                        }
                        .onChange(of: role) { rules = MemberRules.preset($0) } }
                    } header: {
                        Text(L("Who"))
                    } footer: {
                        Text(projectId.isEmpty
                             ? L("This device joins the company account. Mesh access is granted separately after pairing.")
                             : L("Choose a company account with access to every repository in the selected Mesh spaces. The Mesh role below is a separate permission."))
                    }
                    if !projectId.isEmpty { Section {
                        ForEach(availableProjects) { project in
                            Toggle(isOn: Binding(
                                get: { selectedProjectIds.contains(project.projectId) },
                                set: { enabled in
                                    if enabled { selectedProjectIds.insert(project.projectId) }
                                    else if project.projectId != projectId { selectedProjectIds.remove(project.projectId) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.project.name)
                                    Text(project.project.canonicalRepositoryId)
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                            }
                            .disabled(project.projectId == projectId
                                      || selectedAccount.map { !CompanyAccountPolicy.canReceive(project, account: $0) } ?? true)
                        }
                    } header: {
                        Text(L("Mesh spaces and repositories"))
                    } footer: {
                        Text(L("Each selected Mesh keeps its own members and permissions. Linked Mesh spaces are shared only when selected here."))
                    } }
                    if !projectId.isEmpty { Section {
                        Toggle(L("See messages in this Mesh"), isOn: $rules.canSeeChats)
                        Toggle(L("Write messages in this Mesh"), isOn: $rules.canSendToChats)
                        Toggle(L("Post to the Mesh"), isOn: $rules.canPostEvents)
                        Toggle(L("Edit Governance"), isOn: $rules.canEditGovernance)
                        Toggle(L("Create tasks"), isOn: $rules.canCreateTasks)
                        Toggle(L("Use the Mesh executor"), isOn: $rules.canUseProjectExecutor)
                        Toggle(L("Choose an allowed model"), isOn: $rules.canChooseAllowedModel)
                        Toggle(L("Manage Mesh execution"), isOn: $rules.canManageProjectExecution)
                        Toggle(L("Rename computers in this Mesh"), isOn: $rules.canRenameProjectDevices)
                        Toggle(L("Enroll bots"), isOn: $rules.canEnrollBots)
                    } header: {
                        Text(L("May"))
                    } footer: {
                        Text(L("Each answer is checked on this device before reaching a computer. Writing to a Mesh means messages and pauses; approvals stay with its owner."))
                    } }
                    Section {
                        Picker(L("Invite expires after"), selection: $lifetimeMinutes) {
                            Text(L("5 minutes")).tag(5)
                            Text(L("15 minutes")).tag(15)
                        }
                    } header: {
                        Text(L("Link"))
                    } footer: {
                        Text(projectId.isEmpty
                             ? L("One-time pairing. Remove the pending device to revoke its code. The relay keeps it for at most 15 minutes.")
                             : L("One-time pairing. Revoke it by removing the pending member. The relay keeps a code for at most 15 minutes."))
                    }
                    Section {
                        Button(creating ? L("Creating invite…")
                              : (projectId.isEmpty ? L("Create device code") : L("Create invite"))) { create() }
                            .disabled(creating || !accountCoversSelection)
                            .accessibilityIdentifier("members.create-invite")
                    } footer: {
                        Text(accountCoversSelection
                             ? (projectId.isEmpty
                                ? L("The recipient scans this code in Settings → Connections. No Mesh is shared yet.")
                                : L("The recipient scans this invite under Mesh → Join a Mesh. Access starts only after that device connects."))
                             : L("Grant the account every repository in the selected Mesh spaces before inviting its device."))
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            QRCodeImage(text: invite)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        Text(invite).font(.caption.monospaced()).textSelection(.enabled)
                        Button(L("Copy invite")) { UIPasteboard.general.string = invite }
                        Button { showShare = true } label: {
                            Label(L("Share invite"), systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text(L("Scan on the recipient device"))
                    } footer: {
                        Text(String(format: L("Good once, for %d minutes. If it expires, invite again."), lifetimeMinutes))
                    }
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(Theme.riskHigh) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(projectId.isEmpty ? L("Add controller device") : L("Invite a person"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) { MemberInviteShareSheet(uri: invite) }
        }
    }

    private func create() {
        Task { @MainActor in await performCreate() }
    }

    /// The button's work, awaited: the invite, or the reason there is none.
    func performCreate() async {
        creating = true
        error = ""
        do {
            invite = try await model.createMemberInvite(
                projectId: projectId, name: name, role: role, rules: rules,
                lifetimeMinutes: lifetimeMinutes, projectIds: selectedProjectIds,
                accountId: selectedAccountId, parker: parker
            )
        } catch {
            self.error = error.localizedDescription
        }
        creating = false
    }
}
