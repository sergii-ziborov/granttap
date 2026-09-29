import SwiftUI

struct ProjectMembersView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showInvite = false

    var computers: [ProjectComputerSummary] {
        let bindings = snapshot.bindings ?? []
        return ProjectManagePresentation.endpointIds(snapshot).map { endpoint in
            let matches = bindings.filter { $0.endpointId == endpoint }
            let repositories = Set(matches.map(\.repositoryId)).count
            let executionAvailable = snapshot.executions.contains {
                $0.computerId == endpoint && $0.endedAt == nil
            }
            return ProjectComputerSummary(
                endpointId: endpoint,
                displayName: computerName(endpoint),
                repositoryCount: repositories,
                available: matches.isEmpty ? executionAvailable : matches.contains(where: \.available)
            )
        }
    }

    var body: some View {
        let controller = ProjectControllerDevice.current
        List {
            // The current device's key receipt and computer membership are
            // reported independently.
            Section {
                HStack(spacing: 12) {
                    Image(systemName: controller.symbol)
                        .font(.title2).foregroundColor(Theme.codex)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(controller.titleKey))
                            .accessibilityIdentifier("members.controller-device")
                        Text(holdsKey
                             ? L("Holds this Mesh key")
                             : L("Has not received this Mesh key"))
                            .font(.caption).foregroundColor(Theme.muted)
                    }
                }
                if let sharedBy {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2).foregroundColor(Theme.codex)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: L("Shared with you by %@"), sharedBy))
                            Text(L("Their device forwards this Mesh with the role they gave you. Add a computer of your own below to work in it."))
                                .font(.caption).foregroundColor(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("members.shared-by")
                }
            } header: {
                Text(L("Controller"))
            }
            peopleSection
            Section {
                if computers.isEmpty {
                    Text(L("No computer has reported this Mesh yet."))
                        .foregroundColor(Theme.muted)
                } else {
                    ForEach(computers) { computer in
                        NavigationLink {
                            ProjectComputerAccessView(
                                snapshot: snapshot, computer: computer, model: model
                            )
                        } label: {
                            ProjectComputerRow(
                                computer: computer,
                                work: ProjectComputerWork.current(
                                    snapshot: snapshot, endpointId: computer.endpointId, sessions: model.sessions
                                )
                            )
                        }
                    }
                }
            } header: {
                Text(L("Computers"))
            } footer: {
                Text(L("Each Mesh is encrypted with its own key. A computer joins after an authorized device shares that key."))
            }
            unboundSection
        }
        .pageNavigationTitle(L("Members / Computers"))
        .sheet(isPresented: $showInvite) {
            MemberInviteSheet(projectId: snapshot.projectId, model: model)
        }
    }

    /// People receiving this Project through an authorized device link.
    private var peopleSection: some View {
        Section {
            ForEach(model.memberLinks.filter { $0.allowsProject(snapshot.projectId) }
                .sorted { $0.createdAt < $1.createdAt }) { link in
                NavigationLink {
                    MemberLinkDetailView(linkId: link.id, model: model)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2).foregroundColor(Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.name).foregroundColor(Theme.ink)
                            Text("\(link.role.title) · \(link.rules.summary)")
                                .font(.caption).foregroundColor(Theme.muted)
                            if let accountId = link.companyAccountId,
                               let account = model.companyAccounts.first(where: { $0.id == accountId }) {
                                Text(String(format: L("Company account: %@"), account.name))
                                    .font(.caption2).foregroundColor(Theme.muted)
                            }
                            Text(MemberLinkPresentation.stateLabel(link.state(
                                now: Date().timeIntervalSince1970 * 1_000,
                                connected: model.isMemberLinkConnected(link.id)
                            )))
                            .font(.caption2).foregroundColor(
                                model.isMemberLinkConnected(link.id) ? Theme.ok : Theme.muted
                            )
                            if !model.memberCanAccessProject(link, projectId: snapshot.projectId) {
                                Text(L("Blocked by company repository grant"))
                                    .font(.caption2).foregroundStyle(Theme.riskHigh)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("members.link.\(link.id)")
            }
            // The owner controls whether a shared Project may be forwarded.
            if sharedBy == nil {
                Button {
                    showInvite = true
                } label: {
                    Label(L("Invite a person"), systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("members.invite")
            }
        } header: {
            Text(L("People"))
        } footer: {
            Text(sharedBy == nil
                 ? L("Each invite grants selected Mesh spaces and a role. Company repository access is managed in Settings.")
                 : L("This Mesh was shared with this device. Its owner controls further invitations and permissions."))
        }
    }

    /// Paired computers this Project does not reach yet, each with the grant
    /// that would let it in.
    @ViewBuilder private var unboundSection: some View {
        let unbound = ProjectMembership.unbound(
            snapshot: snapshot, paired: model.connectionRegistry.connections
        )
        if !unbound.isEmpty {
            Section {
                ForEach(unbound) { computer in
                    admissionRow(computer)
                }
            } header: {
                Text(L("Not in this Mesh"))
            } footer: {
                Text(L("Adding a computer hands it this Mesh's key over the pairing you already trust. Pairing a new computer is done in Settings."))
            }
        }
    }

    private func admissionRow(_ computer: UnboundProjectComputer) -> some View {
        let participating = model.meshProjectSourceRooms[snapshot.projectId] ?? []
        let admissible = ProjectMeshAdmission.canAdmit(
            target: computer.endpointId, participating: participating,
            paired: model.connectionRegistry.connections
        )
        return HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .frame(width: 24).foregroundColor(Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(computer.displayName).foregroundColor(Theme.ink)
                if !admissible {
                    // Nothing holds the key yet, so there is nothing to copy.
                    Text(L("No computer in this Mesh can share the key yet"))
                        .font(.caption).foregroundColor(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            Button(L("Add")) {
                model.admitComputerToProject(
                    projectId: snapshot.projectId, room: computer.endpointId
                )
            }
            .buttonStyle(.borderless)
            .disabled(!admissible)
        }
        .padding(.vertical, 2)
    }

    /// An authenticated source room has delivered this Mesh's key.
    private var holdsKey: Bool {
        !(model.meshProjectSourceRooms[snapshot.projectId] ?? []).isEmpty
    }

    /// The person whose device this shared Project comes through.
    private var sharedBy: String? {
        ProjectsCatalog.sharedBy(
            snapshot.projectId, rooms: model.meshProjectSourceRooms, connections: model.connectionRegistry.connections
        )
    }

    private func computerName(_ endpoint: String) -> String {
        if let connection = model.connectionRegistry.connections.first(where: { $0.id == endpoint }) {
            return connection.displayName
        }
        guard endpoint.count > 24 else { return endpoint }
        return "\(L("Computer")) \(endpoint.prefix(8))"
    }
}

struct ProjectComputerRow: View {
    let computer: ProjectComputerSummary
    var work: [ProjectComputerWork.Item] = []

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .frame(width: 24).foregroundColor(Theme.codex)
            VStack(alignment: .leading, spacing: 3) {
                Text(computer.displayName)
                Text(computer.detail).font(.caption).foregroundColor(Theme.muted)
                if let line = ProjectComputerWork.line(work) {
                    Text(line).font(.caption)
                        .foregroundColor(work.first?.working == true ? Theme.ok : Theme.muted)
                        .lineLimit(2)
                        .accessibilityIdentifier("computer.work.\(computer.endpointId)")
                }
            }
        }
        .padding(.vertical, 2)
    }
}
