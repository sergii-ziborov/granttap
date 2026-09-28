import SwiftUI

/// Owner-managed people and their repository grants. Mesh roles and devices
/// are managed separately on each Project's Members screen.
struct CompanyAccountsView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        List {
            Section {
                TextField(L("Person or account name"), text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("company.account.name")
                Button(L("Add company account")) {
                    if model.createCompanyAccount(name: name) == nil {
                        error = L("Account could not be saved securely. Enter a name and try again.")
                    } else {
                        name = ""
                        error = nil
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("company.account.add")
            } header: {
                Text(L("Company accounts"))
            } footer: {
                Text(L("A company account owns repository permissions. It joins a Mesh only through a separate invite to one of its devices."))
            }
            if let error { Section { Text(error).foregroundStyle(Theme.riskHigh) } }
            Section {
                ForEach(model.companyAccounts) { account in
                    NavigationLink {
                        CompanyAccountDetailView(account: account, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                            Text(summary(account))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("company.account.\(account.id)")
                }
            } header: {
                Text(L("People"))
            } footer: {
                Text(L("Changing repository access stops new Mesh forwarding on this phone. Data already delivered to a device cannot be recalled."))
            }
        }
        .listStyle(.insetGrouped)
        .pageNavigationTitle(L("Company accounts"))
    }

    private func summary(_ account: CompanyAccount) -> String {
        if account.disabled { return L("Access paused") }
        switch account.repositoryAccess {
        case .all: return L("All company repositories")
        case .selected(let ids):
            return String(format: L("%d selected repositories"), ids.count)
        }
    }
}

struct CompanyAccountDetailView: View {
    @ObservedObject var model: AppModel
    @State private var draft: CompanyAccount
    @State private var error: String?
    @State private var showingDeviceInvite = false

    init(account: CompanyAccount, model: AppModel) {
        self.model = model
        _draft = State(initialValue: account)
    }

    private var repositoryIds: [String] {
        let selected: Set<String>
        if case .selected(let ids) = draft.repositoryAccess { selected = ids }
        else { selected = [] }
        return Set(model.companyRepositoryIds).union(selected).sorted()
    }

    var body: some View {
        List {
            Section {
                TextField(L("Name"), text: $draft.name)
                Toggle(L("Pause this account"), isOn: $draft.disabled)
            } footer: {
                Text(L("Pausing prevents this account's devices from receiving new Mesh data or sending actions through this device."))
            }
            Section {
                Toggle(L("All company repositories"), isOn: Binding(
                    get: { if case .all = draft.repositoryAccess { return true }; return false },
                    set: { enabled in
                        draft.repositoryAccess = enabled ? .all : .selected([])
                    }
                ))
                if case .selected = draft.repositoryAccess {
                    ForEach(repositoryIds, id: \.self) { repositoryId in
                        Toggle(isOn: Binding(
                            get: { draft.repositoryAccess.allows(repositoryId) },
                            set: { enabled in
                                guard case .selected(var ids) = draft.repositoryAccess else { return }
                                if enabled { ids.insert(repositoryId) }
                                else { ids.remove(repositoryId) }
                                draft.repositoryAccess = .selected(ids)
                            }
                        )) {
                            Text(repositoryId)
                                .lineLimit(2)
                        }
                        .accessibilityIdentifier("company.repository.\(repositoryId)")
                    }
                }
            } header: {
                Text(L("Repository access"))
            } footer: {
                Text(L("All includes repositories discovered later. Selected grants use stable repository IDs. A Mesh invitation is still required for each Mesh."))
            }
            Section {
                Button(L("Add controller device")) { showingDeviceInvite = true }
                    .disabled(draft.disabled || model.companyAccounts.first(where: { $0.id == draft.id })?.disabled != false)
                    .accessibilityIdentifier("company.device.add")
                ForEach(model.memberLinks.filter { $0.companyAccountId == draft.id }) { link in
                    NavigationLink {
                        MemberLinkDetailView(linkId: link.id, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.name)
                            Text(String(format: L("%d Mesh spaces"), link.projectIds.count))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            } header: {
                Text(L("Controller devices"))
            } footer: {
                Text(L("Pair a phone or tablet with this account even before connecting a computer. Pairing alone grants no Mesh."))
            }
            Section {
                Button(L("Save account")) {
                    error = model.updateCompanyAccount(draft)
                        ? nil : L("Account permissions could not be saved securely.")
                }
                .accessibilityIdentifier("company.account.save")
                if let error { Text(error).foregroundStyle(Theme.riskHigh) }
            }
        }
        .listStyle(.insetGrouped)
        .pageNavigationTitle(draft.name)
        .sheet(isPresented: $showingDeviceInvite) {
            MemberInviteSheet(projectId: "", model: model, initialAccountId: draft.id)
        }
    }
}
