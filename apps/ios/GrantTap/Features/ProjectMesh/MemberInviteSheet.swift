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
    @State private var rules = MemberRules.preset(.member)
    @State private var invite: String
    @State private var error = ""
    @State private var creating = false

    init(projectId: String, model: AppModel, parker: AppModel.MemberInviteParker? = nil, initialInvite: String = "") {
        self.projectId = projectId
        self.model = model
        self.parker = parker
        _invite = State(initialValue: initialInvite)
    }

    var body: some View {
        CompatNavigationStack {
            List {
                if invite.isEmpty {
                    Section {
                        TextField(L("Name"), text: $name)
                        Picker(L("Role"), selection: $role) {
                            ForEach(MemberRole.allCases) { role in Text(role.title).tag(role) }
                        }
                        .onChange(of: role) { rules = MemberRules.preset($0) }
                    } header: {
                        Text(L("Who"))
                    } footer: {
                        Text(role.explanation)
                    }
                    Section {
                        Toggle(L("See the Project's chats"), isOn: $rules.canSeeChats)
                        Toggle(L("Write to the Project's chats"), isOn: $rules.canSendToChats)
                        Toggle(L("Post to the Project"), isOn: $rules.canPostEvents)
                        Toggle(L("Edit Governance"), isOn: $rules.canEditGovernance)
                        Toggle(L("Create tasks"), isOn: $rules.canCreateTasks)
                        Toggle(L("Use the Project executor"), isOn: $rules.canUseProjectExecutor)
                        Toggle(L("Choose an allowed model"), isOn: $rules.canChooseAllowedModel)
                        Toggle(L("Manage Project execution"), isOn: $rules.canManageProjectExecution)
                        Toggle(L("Rename Project devices"), isOn: $rules.canRenameProjectDevices)
                        Toggle(L("Enroll bots"), isOn: $rules.canEnrollBots)
                    } header: {
                        Text(L("May"))
                    } footer: {
                        Text(L("Each answer is checked on this phone before anything reaches a computer. The chats are the Project's on your computers; writing means messages and pauses, never approvals, which stay on this phone."))
                    }
                    Section {
                        Button(creating ? L("Creating invite…") : L("Create invite")) { create() }
                            .disabled(creating)
                            .accessibilityIdentifier("members.create-invite")
                    } footer: {
                        Text(L("The invite is one code, good for 15 minutes. The other phone scans it under Projects → Join a Project, and this phone starts forwarding the Project to it."))
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
                    } header: {
                        Text(L("Scan on the other phone"))
                    } footer: {
                        Text(L("Good once, for 15 minutes. If it expires, invite again."))
                    }
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(Theme.riskHigh) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Invite a person"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
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
                projectId: projectId, name: name, role: role, rules: rules, parker: parker
            )
        } catch {
            self.error = error.localizedDescription
        }
        creating = false
    }
}

/// One member's settings, changed one at a time.
enum MemberLinkEdits {
    static func withRole(_ link: MemberLink, _ role: MemberRole) -> MemberLink {
        var next = link
        next.role = role
        next.rules = MemberRules.preset(role)
        return next
    }

    static func withPosts(_ link: MemberLink, _ allowed: Bool) -> MemberLink {
        var next = link
        next.rules.canPostEvents = allowed
        return next
    }

    static func withGovernance(_ link: MemberLink, _ allowed: Bool) -> MemberLink {
        var next = link
        next.rules.canEditGovernance = allowed
        return next
    }

    static func withChats(_ link: MemberLink, _ allowed: Bool) -> MemberLink {
        var next = link
        next.rules.canSeeChats = allowed
        // Writing into a chat one cannot see is nothing.
        if !allowed { next.rules.canSendToChats = false }
        return next
    }

    static func withChatWriting(_ link: MemberLink, _ allowed: Bool) -> MemberLink {
        var next = link
        next.rules.canSendToChats = allowed
        if allowed { next.rules.canSeeChats = true }
        return next
    }
}

/// One member: what they may do, whether their phone is here, and the way out.
struct MemberLinkDetailView: View {
    let linkId: String
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    var link: MemberLink? { model.memberLinks.first { $0.id == linkId } }

    var body: some View {
        List {
            if let link {
                Section {
                    CompatLabeledContent(L("Status"), value: MemberLinkPresentation.stateLabel(
                        link.state(now: Date().timeIntervalSince1970 * 1_000, connected: model.isMemberLinkConnected(link.id))
                    ))
                    if let joined = link.joinedAt {
                        CompatLabeledContent(L("Joined"), value: MemberLinkPresentation.ago(joined))
                    }
                } footer: {
                    if link.joinedAt == nil {
                        Text(L("Until the invite is scanned, nothing is forwarded. If it has expired, remove this member and invite again."))
                    }
                }
                Section {
                    Picker(L("Role"), selection: Binding(
                        get: { link.role },
                        set: { model.updateMemberLink(MemberLinkEdits.withRole(link, $0)) }
                    )) {
                        ForEach(MemberRole.allCases) { role in Text(role.title).tag(role) }
                    }
                    Toggle(L("See the Project's chats"), isOn: Binding(
                        get: { link.rules.canSeeChats },
                        set: { model.updateMemberLink(MemberLinkEdits.withChats(link, $0)) }
                    ))
                    Toggle(L("Write to the Project's chats"), isOn: Binding(
                        get: { link.rules.canSendToChats },
                        set: { model.updateMemberLink(MemberLinkEdits.withChatWriting(link, $0)) }
                    ))
                    Toggle(L("Post to the Project"), isOn: Binding(
                        get: { link.rules.canPostEvents },
                        set: { model.updateMemberLink(MemberLinkEdits.withPosts(link, $0)) }
                    ))
                    Toggle(L("Edit Governance"), isOn: Binding(
                        get: { link.rules.canEditGovernance },
                        set: { model.updateMemberLink(MemberLinkEdits.withGovernance(link, $0)) }
                    ))
                    Toggle(L("Create tasks"), isOn: Binding(
                        get: { link.rules.canCreateTasks },
                        set: { var next = link; next.rules.canCreateTasks = $0; model.updateMemberLink(next) }
                    ))
                    Toggle(L("Use the Project executor"), isOn: Binding(
                        get: { link.rules.canUseProjectExecutor },
                        set: { var next = link; next.rules.canUseProjectExecutor = $0; model.updateMemberLink(next) }
                    ))
                    Toggle(L("Choose an allowed model"), isOn: Binding(
                        get: { link.rules.canChooseAllowedModel },
                        set: { var next = link; next.rules.canChooseAllowedModel = $0; model.updateMemberLink(next) }
                    ))
                    Toggle(L("Manage Project execution"), isOn: Binding(
                        get: { link.rules.canManageProjectExecution },
                        set: { var next = link; next.rules.canManageProjectExecution = $0; model.updateMemberLink(next) }
                    ))
                    Toggle(L("Rename Project devices"), isOn: Binding(
                        get: { link.rules.canRenameProjectDevices },
                        set: { var next = link; next.rules.canRenameProjectDevices = $0; model.updateMemberLink(next) }
                    ))
                    Toggle(L("Enroll bots"), isOn: Binding(
                        get: { link.rules.canEnrollBots },
                        set: { var next = link; next.rules.canEnrollBots = $0; model.updateMemberLink(next) }
                    ))
                } header: {
                    Text(L("May"))
                } footer: {
                    Text(L("Takes effect at once: this phone checks each answer before forwarding what the member's phone sends."))
                }
                Section {
                    Button(L("Remove member"), role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("members.remove")
                } footer: {
                    Text(L("Their phone stops receiving the Project at once. Nothing they already saw can be recalled."))
                }
            } else {
                Text(L("This member was removed.")).foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(link?.name ?? L("Member"))
        .confirmationDialog(L("Remove this member?"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(L("Remove member"), role: .destructive) {
                model.removeMemberLink(id: linkId)
                dismiss()
            }
        }
    }
}

enum MemberLinkPresentation {
    static func stateLabel(_ state: MemberLinkState) -> String {
        switch state {
        case .waiting(let expiresAt):
            let minutes = max(0, Int((expiresAt - Date().timeIntervalSince1970 * 1_000) / 60_000))
            return String(format: L("Waiting for the scan · %d min left"), minutes)
        case .expired: return L("Invite expired")
        case .connected: return L("Connected")
        case .offline(let lastSeenAt):
            return lastSeenAt.map { String(format: L("Offline · seen %@"), ago($0)) } ?? L("Offline")
        }
    }

    static func ago(_ at: Double) -> String {
        RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: at / 1_000), relativeTo: Date())
    }
}
