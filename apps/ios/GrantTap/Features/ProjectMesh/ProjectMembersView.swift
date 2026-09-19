import SwiftUI

struct ProjectMembersView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showPairing = false
    @State private var showInvite = false
    @State private var roomsBeforePairing: Set<String> = []

    var computers: [ProjectComputerSummary] {
        summaries(
            for: ProjectComputerRoster.memberIds(
                snapshot: snapshot,
                participating: model.computerRooms(for: snapshot.projectId),
                memberRooms: Set(model.memberLinks(for: snapshot.projectId).map(\.id)),
                hidden: model.hiddenComputers(for: snapshot.projectId)
            )
        )
    }

    var archived: [ProjectComputerSummary] {
        summaries(
            for: ProjectComputerRoster.archivedIds(
                snapshot: snapshot,
                archived: model.archivedComputers(for: snapshot.projectId)
            )
        )
    }

    private func summaries(for endpoints: [String]) -> [ProjectComputerSummary] {
        let bindings = snapshot.bindings ?? []
        return endpoints.map { endpoint in
            let matches = bindings.filter { $0.endpointId == endpoint }
            let repositories = Set(matches.map(\.repositoryId)).count
            let executionAvailable = snapshot.executions.contains {
                $0.computerId == endpoint && $0.endedAt == nil
            }
            return ProjectComputerSummary(
                endpointId: endpoint,
                displayName: model.displayName(forComputer: endpoint),
                repositoryCount: repositories,
                available: matches.isEmpty ? executionAvailable : matches.contains(where: \.available)
            )
        }
    }

    var body: some View {
        List {
            // "You / Current account" said nothing true: no agent runs on the
            // phone, and a Project has no accounts. What the phone actually is
            // here is the holder of the Project key and the only party paired
            // with every computer -- which is why adding one happens from here.
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "iphone.gen3")
                        .font(.title2).foregroundColor(Theme.codex)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("This iPhone"))
                        Text(holdsKey
                             ? L("Holds this Project's mesh key")
                             : L("Has not received this Project's mesh key"))
                            .font(.caption).foregroundColor(Theme.muted)
                    }
                }
                if let sharedBy {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2).foregroundColor(Theme.codex)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: L("Shared with you by %@"), sharedBy))
                            Text(L("Their phone forwards the Project with the role they gave you. Add a computer of your own below to work in it."))
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
                    Text(L("No computer has reported this Project yet."))
                        .foregroundColor(Theme.muted)
                } else {
                    ForEach(computers) { computer in
                        NavigationLink {
                            ProjectComputerDetailView(
                                endpointId: computer.endpointId, snapshot: snapshot, model: model
                            )
                        } label: {
                            ProjectComputerRow(
                                computer: computer,
                                work: ProjectComputerWork.current(
                                    snapshot: snapshot, endpointId: computer.endpointId, sessions: model.sessions
                                )
                            )
                        }
                        .accessibilityIdentifier("members.computer.\(computer.endpointId)")
                    }
                }
            } header: {
                Text(L("Computers"))
            } footer: {
                Text(L("The mesh is encrypted under a key of its own. A computer takes part once this phone hands it that key."))
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { computer in
                        NavigationLink {
                            ProjectComputerDetailView(
                                endpointId: computer.endpointId, snapshot: snapshot, model: model
                            )
                        } label: {
                            ProjectComputerRow(
                                computer: computer,
                                work: ProjectComputerWork.current(
                                    snapshot: snapshot, endpointId: computer.endpointId, sessions: model.sessions
                                )
                            )
                        }
                        .accessibilityIdentifier("members.archived.\(computer.endpointId)")
                    }
                } header: {
                    Text(L("Archived computers"))
                }
            }
            unboundSection
        }
        .navigationTitle(L("Members / Computers"))
        .sheet(isPresented: $showPairing) {
            // Someone else's Project arrives by itself once their phone is
            // scanned; nothing is admitted into this one.
            PairingSheet(purpose: .joinProject, onPaired: {}).environmentObject(model)
        }
        .sheet(isPresented: $showInvite) {
            MemberInviteSheet(projectId: snapshot.projectId, model: model)
        }
    }

    /// People whose phones this phone forwards the Project to, and the way to
    /// add one — or to join a Project from someone else's phone.
    private var peopleSection: some View {
        Section {
            ForEach(model.memberLinks(for: snapshot.projectId)) { link in
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
                            Text(MemberLinkPresentation.stateLabel(link.state(
                                now: Date().timeIntervalSince1970 * 1_000,
                                connected: model.isMemberLinkConnected(link.id)
                            )))
                            .font(.caption2).foregroundColor(
                                model.isMemberLinkConnected(link.id) ? Theme.ok : Theme.muted
                            )
                        }
                    }
                }
                .accessibilityIdentifier("members.link.\(link.id)")
            }
            // A Project shared with this phone is someone else's to share on:
            // the rules they set for this phone cannot reach a third one.
            if sharedBy == nil {
                Button {
                    showInvite = true
                } label: {
                    Label(L("Invite a person"), systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("members.invite")
            }
            Button {
                roomsBeforePairing = Set(model.connectionRegistry.connections.map(\.id))
                showPairing = true
            } label: {
                Label(L("Join a Project from another phone"), systemImage: "qrcode")
            }
            .accessibilityIdentifier("members.join")
        } header: {
            Text(L("People"))
        } footer: {
            Text(sharedBy == nil
                 ? L("An invited phone receives this Project's Tasks, computers and Governance through this phone, with the rules you set. To join someone else's Project, scan the invite their phone shows.")
                 : L("This Project came to you from someone else's phone; inviting others to it is theirs to do. To join another Project, scan the invite its owner's phone shows."))
        }
    }

    /// Admit whatever the sheet just paired, so one action does both.
    private func admitNewlyPaired() {
        model.admitNewlyPairedComputers(
            projectId: snapshot.projectId, pairedBefore: roomsBeforePairing
        )
    }

    /// Paired computers this Project does not reach yet, each with the grant
    /// that would let it in.
    @ViewBuilder private var unboundSection: some View {
        let unbound = ProjectMembership.unbound(
            snapshot: snapshot,
            paired: model.connectionRegistry.connections,
            removed: model.removedComputers(for: snapshot.projectId)
        )
        if !unbound.isEmpty {
            Section {
                ForEach(unbound) { computer in
                    admissionRow(computer)
                }
            } header: {
                Text(L("Not in this Project"))
            } footer: {
                Text(L("Adding a computer hands it this Project's mesh key over the pairing you already trust. Pairing a new computer is done in Settings."))
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
                    Text(L("No computer in this Project can share the key yet"))
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

    /// The phone takes part by holding the key it hands to computers.
    private var holdsKey: Bool {
        !(model.meshProjectSourceRooms[snapshot.projectId] ?? []).isEmpty
    }

    /// The person whose phone this Project comes through, when it is theirs.
    private var sharedBy: String? {
        ProjectsCatalog.sharedBy(
            snapshot.projectId, rooms: model.meshProjectSourceRooms, connections: model.connectionRegistry.connections
        )
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
