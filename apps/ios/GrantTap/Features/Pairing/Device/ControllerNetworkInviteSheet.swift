import SwiftUI

struct ControllerNetworkInviteSheet: View {
    var initialMachineId: String? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = ControllerInviteCoordinator.shared
    @State private var accountURI: String?
    @State private var accountError: String?
    @State private var accountBusy = false
    @State private var showDirectNetwork = false
    @State private var selectedRoom: String?
    @State private var accountComputers: [AccountComputer] = []
    @State private var computerBusy: String?
    @State private var computerError: String?
    @State private var projectInviteId = ""
    @State private var showProjectInvite = false

    var body: some View {
        CompatNavigationStack {
            ScrollViewReader { proxy in
                List {
                    accountSection
                    directNetworkSection
                    computerSection
                    projectSection
                }
                .onChange(of: selectedRoom) { room in
                    guard room != nil else { return }
                    withAnimation { proxy.scrollTo("computer-invite-selected", anchor: .top) }
                }
            }
            .navigationTitle(L("Add a controller"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showProjectInvite) {
                MemberInviteSheet(projectId: projectInviteId, model: model)
            }
            .task {
                if let initialMachineId,
                   let existing = model.connectionRegistry.connections.first(where: {
                       $0.linkedMachineId == initialMachineId
                   }) {
                    selectedRoom = existing.id
                    coordinator.start(using: model, roomId: existing.id)
                }
                guard let session = GrantTapAccountAPI.session else { return }
                do {
                    accountComputers = try await AccountRecovery.computers(session: session)
                    if let initialMachineId, selectedRoom == nil {
                        guard let computer = accountComputers.first(where: { $0.id == initialMachineId })
                        else { computerError = L("This computer is no longer in the account."); return }
                        await openAccountComputer(computer)
                    }
                } catch {
                    if selectedRoom == nil {
                        computerError = L("Could not load account computers. Check the connection and try again.")
                    }
                }
            }
        }
    }

    @ViewBuilder private var directNetworkSection: some View {
        if model.connectionRegistry.connections.contains(where: { !$0.pairing.isHub }) {
            Section(L("Computers already linked to this iPhone")) {
                Text(L("This QR copies the currently reachable computer links to another iPhone. It does not join an account or include computers added later."))
                    .foregroundStyle(Theme.muted)
                Button(L("Prepare QR for linked computers")) {
                    selectedRoom = nil
                    showDirectNetwork = true
                    coordinator.start(using: model)
                }
                if showDirectNetwork {
                    ForEach(coordinator.entries) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            if entry.uri != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                            } else if let error = entry.error {
                                Text(error).foregroundStyle(Theme.riskHigh)
                            } else { ProgressView() }
                        }
                    }
                    ForEach(coordinator.omittedComputerNames, id: \.self) { name in
                        Text(String(format: L("%@ is offline and will not be included."), name))
                            .foregroundStyle(Theme.muted)
                    }
                    if let uri = coordinator.bundleURI {
                        HStack { Spacer(); QRCodeImage(text: uri); Spacer() }
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("devices.network-invite-qr")
                    } else {
                        Button(L("Show linked-computers QR")) {
                            Task { await coordinator.publish() }
                        }
                        .disabled(!coordinator.readyToPublish || coordinator.publishing)
                    }
                    if let error = coordinator.error { Text(error).foregroundStyle(Theme.riskHigh) }
                }
            }
        }
    }

    @ViewBuilder private var accountSection: some View {
        Section(L("Entire Account Mesh")) {
            if let session = GrantTapAccountAPI.session {
                Text(L("One QR joins this account and discovers every linked MCP computer, including computers added later. Each computer still provides its own secure chat route."))
                    .foregroundStyle(Theme.muted)
                Button {
                    Task { await issueAccountQR(session) }
                } label: {
                    if accountBusy { ProgressView() }
                    else { Label(L("Show Account Mesh QR"), systemImage: "qrcode") }
                }
                .disabled(accountBusy)
                if let accountURI {
                    HStack { Spacer(); QRCodeImage(text: accountURI); Spacer() }
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("devices.account-invite-qr")
                    Text(L("Scan on the new iPhone or iPad. One use; expires in five minutes. This grants full account access."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            } else {
                Text(L("Sign in with a passkey to show one QR for your whole Account Mesh."))
                    .foregroundStyle(Theme.muted)
            }
            if let accountError { Text(accountError).foregroundStyle(Theme.riskHigh) }
        }
    }

    @ViewBuilder private var computerSection: some View {
        Section(L("One computer")) {
            Text(L("A computer QR links only that computer. Its MCP must be online to issue a one-time key."))
                .foregroundStyle(Theme.muted)
            ForEach(accountComputers) { computer in
                Button {
                    showDirectNetwork = false
                    Task { await openAccountComputer(computer) }
                } label: {
                    if computerBusy == computer.id { ProgressView() }
                    else { Label(computer.name, systemImage: "desktopcomputer") }
                }
                .disabled(computerBusy != nil)
            }
            ForEach(model.connectionRegistry.connections.filter { connection in
                !connection.pairing.isHub && (connection.linkedMachineId == nil ||
                    !accountComputers.contains(where: { $0.id == connection.linkedMachineId }))
            }) { computer in
                Button(computer.displayName) {
                    showDirectNetwork = false
                    selectedRoom = computer.id
                    coordinator.start(using: model, roomId: computer.id)
                }
            }
            if let computerError { Text(computerError).foregroundStyle(Theme.riskHigh) }
            if let selectedRoom {
                let name = model.connectionRegistry.connections.first { $0.id == selectedRoom }?.displayName
                    ?? L("Computer")
                Text(name).font(.headline).id("computer-invite-selected")
                ForEach(coordinator.entries) { entry in
                    if entry.uri != nil {
                        Label(L("Ready"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.ok)
                    } else if let error = entry.error {
                        Text(error).foregroundStyle(Theme.riskHigh)
                    } else { ProgressView(L("Requesting computer key…")) }
                }
                if let uri = coordinator.bundleURI {
                    HStack { Spacer(); QRCodeImage(text: uri); Spacer() }
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("devices.computer-invite-qr")
                    Text(L("Scan on the new iPhone or iPad. This QR links only the selected computer."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    Button(L("Show this computer QR")) { Task { await coordinator.publish() } }
                        .disabled(!coordinator.readyToPublish || coordinator.publishing)
                    Button(L("Retry computer")) { coordinator.start(using: model, roomId: selectedRoom) }
                }
                if let error = coordinator.error { Text(error).foregroundStyle(Theme.riskHigh) }
                if coordinator.entries.isEmpty {
                    Text(L("This computer is not Live. Open its GrantTap MCP connection card to show its own QR."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder private var projectSection: some View {
        Section(L("One Project Mesh")) {
            Text(L("A Project Mesh QR is a separate, role-limited invitation. It never grants the whole account or other computers."))
                .foregroundStyle(Theme.muted)
            ForEach(model.meshSnapshots.values.sorted { $0.project.name < $1.project.name },
                    id: \.projectId) { project in
                Button(project.project.name) {
                    projectInviteId = project.projectId
                    showProjectInvite = true
                }
            }
        }
    }

    private func issueAccountQR(_ session: GrantTapAccountSession) async {
        accountBusy = true
        accountError = nil
        accountURI = nil
        defer { accountBusy = false }
        do { accountURI = try await GrantTapAccountAPI.issueDeviceInvite(session) }
        catch { accountError = L("Could not create an Account Mesh QR. Check the account connection and try again.") }
    }

    private func openAccountComputer(_ computer: AccountComputer) async {
        computerError = nil
        if let existing = model.connectionRegistry.connections.first(where: {
            $0.linkedMachineId == computer.id
        }) {
            selectedRoom = existing.id
            coordinator.start(using: model, roomId: existing.id)
            return
        }
        guard let session = GrantTapAccountAPI.session else { return }
        computerBusy = computer.id
        defer { computerBusy = nil }
        do {
            let pairing = try await AccountRecovery.connect(computer, session: session,
                                                            maxPollAttempts: 10)
            guard model.addRecoveredAccountConnections([
                RecoveredAccountConnection(machineId: computer.id, pairing: pairing)
            ], accountId: session.accountId) else { throw AccountBridgeError.storage }
            selectedRoom = pairing.room
            coordinator.start(using: model, roomId: pairing.room)
        } catch {
            computerError = L("This computer could not establish a secure chat link. Open GrantTap MCP on that computer and retry.")
        }
    }
}
