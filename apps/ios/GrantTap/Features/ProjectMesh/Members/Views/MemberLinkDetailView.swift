import SwiftUI

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
    @State private var saveError: String?
    @State private var pendingAccountId = ""

    var link: MemberLink? { model.memberLinks.first { $0.id == linkId } }

    var body: some View {
        List {
            if let link {
                Section {
                    CompatLabeledContent(L("Status"), value: MemberLinkPresentation.stateLabel(
                        link.state(now: Date().timeIntervalSince1970 * 1_000, connected: model.isMemberLinkConnected(link.id))
                    ))
                    if let accountId = link.companyAccountId {
                        CompatLabeledContent(
                            L("Company account"),
                            value: model.companyAccounts.first(where: { $0.id == accountId })?.name
                                ?? L("Account unavailable")
                        )
                    } else {
                        Text(L("Legacy device invite: no company account is assigned yet."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let joined = link.joinedAt {
                        CompatLabeledContent(L("Joined"), value: MemberLinkPresentation.ago(joined))
                    }
                    if let uri = link.inviteURI, link.joinedAt == nil,
                       link.inviteExpiresAt > Date().timeIntervalSince1970 * 1_000 {
                        MemberInviteLinkSection(uri: uri, expiresAt: link.inviteExpiresAt)
                    }
                } footer: {
                    if link.joinedAt == nil {
                        Text(L("Until the invite is scanned, nothing is forwarded. If it has expired, remove this member and invite again."))
                    }
                }
                if link.companyAccountId == nil {
                    Section {
                        Picker(L("Company account"), selection: $pendingAccountId) {
                            Text(L("Choose account")).tag("")
                            ForEach(model.companyAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        Button(L("Assign account to this device")) {
                            saveError = model.assignCompanyAccount(pendingAccountId, to: link.id)
                                ? nil : L("Account could not be assigned securely.")
                        }
                        .disabled(pendingAccountId.isEmpty)
                    } footer: {
                        Text(L("Assigning an account starts its repository gate immediately. This device keeps only separately selected Mesh spaces."))
                    }
                }
                Section {
                    Picker(L("Role"), selection: Binding(
                        get: { link.role },
                        set: { save(MemberLinkEdits.withRole(link, $0)) }
                    )) {
                        ForEach(MemberRole.allCases) { role in Text(role.title).tag(role) }
                    }
                    Toggle(L("See messages in this Mesh"), isOn: Binding(
                        get: { link.rules.canSeeChats },
                        set: { save(MemberLinkEdits.withChats(link, $0)) }
                    ))
                    Toggle(L("Write messages in this Mesh"), isOn: Binding(
                        get: { link.rules.canSendToChats },
                        set: { save(MemberLinkEdits.withChatWriting(link, $0)) }
                    ))
                    Toggle(L("Post to the Mesh"), isOn: Binding(
                        get: { link.rules.canPostEvents },
                        set: { save(MemberLinkEdits.withPosts(link, $0)) }
                    ))
                    Toggle(L("Edit Governance"), isOn: Binding(
                        get: { link.rules.canEditGovernance },
                        set: { save(MemberLinkEdits.withGovernance(link, $0)) }
                    ))
                    Toggle(L("Create tasks"), isOn: ruleBinding(link, \.canCreateTasks))
                    Toggle(L("Use the Mesh executor"), isOn: ruleBinding(link, \.canUseProjectExecutor))
                    Toggle(L("Choose an allowed model"), isOn: ruleBinding(link, \.canChooseAllowedModel))
                    Toggle(L("Manage Mesh execution"), isOn: ruleBinding(link, \.canManageProjectExecution))
                    Toggle(L("Rename computers in this Mesh"), isOn: ruleBinding(link, \.canRenameProjectDevices))
                    Toggle(L("Enroll bots"), isOn: ruleBinding(link, \.canEnrollBots))
                } header: {
                    Text(L("May"))
                } footer: {
                    Text(L("Takes effect at once: this phone checks each answer before forwarding what the member's phone sends."))
                }
                MemberProjectAccessSection(link: link, model: model)
                if let saveError {
                    Section { Text(saveError).foregroundStyle(Theme.riskHigh) }
                }
                Section {
                    Button(L("Remove member"), role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("members.remove")
                } footer: {
                    Text(L("New Mesh messages stop. Messages already sent through the relay may still arrive until they expire."))
                }
            } else {
                Text(L("This member was removed.")).foregroundStyle(Theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .pageNavigationTitle(link?.name ?? L("Member"))
        .confirmationDialog(L("Remove this member?"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(L("Remove member"), role: .destructive) {
                if model.removeMemberLink(id: linkId) { dismiss() }
                else { saveError = L("Member access could not be revoked securely.") }
            }
        }
    }

    private func ruleBinding(
        _ link: MemberLink,
        _ keyPath: WritableKeyPath<MemberRules, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { link.rules[keyPath: keyPath] },
            set: { value in
                var next = link
                next.rules[keyPath: keyPath] = value
                save(next)
            }
        )
    }

    private func save(_ link: MemberLink) {
        saveError = model.updateMemberLink(link) ? nil : L("Member permissions could not be saved securely.")
    }
}

enum MemberLinkPresentation {
    static func stateLabel(_ state: MemberLinkState) -> String {
        switch state {
        case .waiting(let expiresAt):
            let minutes = max(0, Int((expiresAt - Date().timeIntervalSince1970 * 1_000) / 60_000))
            return String(format: L("Waiting for the scan · %d min left"), minutes)
        case .expired: return L("Invite expired")
        case .connected: return L("Joined · relay connected")
        case .offline(let lastSeenAt):
            return lastSeenAt.map { String(format: L("Relay offline · last activity %@"), ago($0)) }
                ?? L("Relay offline")
        }
    }

    static func ago(_ at: Double) -> String {
        RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: at / 1_000), relativeTo: Date())
    }
}
