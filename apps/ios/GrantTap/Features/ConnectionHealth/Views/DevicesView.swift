import SwiftUI

/// The account-wide Mesh exists independently of computers and Project Meshes.
/// Adding a device only contributes an execution route to that account.
struct DevicesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var subscription = SubscriptionStore.shared
    var localComputer: String?
    var localAccountLinked: Bool?
    var localPaired: Bool?
    var localRelayStatus: String?
    var localPhoneReachability: String?
    @State private var showPairing = false
    @State private var showControllerInvite = false
    @State private var inviteMachineId: String?
    @State private var showForgetConfirmation = false
    @State private var accountSession = GrantTapAccountAPI.session
    @StateObject private var roster = AccountDeviceRoster()
    #if !targetEnvironment(macCatalyst)
    @State private var controllerName = ControllerDisplayName.current()
    @State private var controllerNameError: String?
    #endif
    #if targetEnvironment(macCatalyst)
    @EnvironmentObject private var localMCP: MacLocalMCPModel
    @State private var localLinkBusy = false
    @State private var localLinkError: String?
    #endif

    var body: some View {
        List {
            #if !targetEnvironment(macCatalyst)
            Section {
                TextField(L("Device name"), text: $controllerName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("devices.controller-name")
                Button(L("Save device name")) {
                    if ControllerDisplayName.save(controllerName) {
                        controllerName = ControllerDisplayName.current()
                        controllerNameError = nil
                        model.announceControllerName()
                    } else {
                        controllerNameError = L("Use a name of up to 80 characters.")
                    }
                }
                .accessibilityIdentifier("devices.save-controller-name")
                if let controllerNameError {
                    Text(controllerNameError)
                        .foregroundStyle(Theme.riskHigh)
                        .accessibilityIdentifier("devices.controller-name-error")
                }
            } header: {
                Text(L("This device"))
            } footer: {
                Text(L("This name identifies your iPhone or iPad to linked computers."))
            }
            #endif
            Section {
                AccountConnectionView(
                    embedded: true,
                    onLinkLocal: linkLocalAccount,
                    onAccountReady: {
                        accountSession = GrantTapAccountAPI.session
                        model.refreshAccountDeviceCatalog()
                        Task {
                            await subscription.refreshBetaRelayAccess()
                            await loadAccountDevices(force: true)
                        }
                    },
                    onAccountSignedOut: {
                        accountSession = nil
                        roster.clear()
                        model.stopAccountSpaceSync()
                        model.refreshAccountDeviceCatalog()
                        Task { await subscription.refreshBetaRelayAccess() }
                    },
                    onAccountDeleted: { try model.clearDeletedAccountLinks($0) }
                )
                .padding(.vertical, 8)
            } header: {
                Text(L("Account Mesh"))
            } footer: {
                Text(L("Your Account Mesh exists on the relay even with no computers. A Project Mesh coordinates one project; each Task keeps its own computer route."))
            }

            if accountSession != nil {
                Section(L("Account devices")) {
                    if roster.isLoading && roster.computers.isEmpty {
                        ProgressView(L("Loading devices…"))
                    }
                    if let error = roster.error {
                        Button(error) { Task { await loadAccountDevices(force: true) } }
                    }
                    if roster.computers.isEmpty && !roster.isLoading && roster.error == nil {
                        Text(L("No devices yet. Your Account Mesh is ready."))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(roster.computers) { computer in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(computer.name, systemImage: "desktopcomputer")
                                Spacer()
                                Text(accountComputerStatus(computer))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            #if !targetEnvironment(macCatalyst)
                            Button(L("Show QR for this computer")) {
                                inviteMachineId = computer.id
                                showControllerInvite = true
                            }
                            if needsRelayVerification(computer) {
                                Button(L("Verify app relay access")) {
                                    Task {
                                        await subscription.verifyBetaRelayAccess()
                                        if subscription.allowsManagedTransport {
                                            await retryAccountComputer(computer)
                                        }
                                    }
                                }
                                if let error = subscription.betaVerificationError {
                                    Text(error).font(.caption).foregroundStyle(Theme.riskMed)
                                }
                            } else if AccountComputerChatStatus.canRetry(
                                online: isOnline(computer),
                                hasChats: accountComputerHasChats(computer)
                            ) {
                                Button(L("Retry secure chat link")) {
                                    Task { await retryAccountComputer(computer) }
                                }
                            }
                            #endif
                        }
                    }
                    #if !targetEnvironment(macCatalyst)
                    if let error = model.accountSpaceSyncError {
                        Text(error).font(.caption).foregroundStyle(Theme.riskMed)
                    }
                    #endif
                }
            }

            #if targetEnvironment(macCatalyst)
            if accountSession != nil && localAccountLinked != true {
                Section(L("This Mac")) {
                    Label(L("Link this Mac to your Account Mesh"),
                          systemImage: "desktopcomputer.and.arrow.down")
                    if localComputer != nil {
                        Button(L("Link this Mac")) { Task { await linkCurrentMac() } }
                            .disabled(localLinkBusy)
                    }
                    if localLinkBusy { ProgressView(L("Connecting…")) }
                    if let localLinkError { Text(localLinkError).foregroundStyle(Theme.riskHigh) }
                }
            }
            MacLocalMCPSettingsSection(
                computer: localComputer, paired: localPaired,
                relayStatus: localRelayStatus,
                phoneReachability: localPhoneReachability
            )
            #else
            SettingsConnectionSection(
                onPair: { showPairing = true },
                onInviteController: {
                    inviteMachineId = nil
                    showControllerInvite = true
                },
                onForgetAll: { showForgetConfirmation = true },
                localComputer: localComputer,
                accountId: accountSession?.accountId,
                accountMachineIds: Set(roster.computers.map(\.id))
            )
            #endif
        }
        .accessibilityIdentifier("devices.page")
        .pageNavigationTitle(L("Devices"), showsBack: false)
        .refreshable { await loadAccountDevices(force: true) }
        .onAppear { Task { await loadAccountDevices() } }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await loadAccountDevices() } }
        }
        #if targetEnvironment(macCatalyst)
        .task(id: localComputer) {
            if accountSession != nil, localComputer != nil, localAccountLinked != true {
                await linkCurrentMac()
            }
        }
        #endif
        .sheet(isPresented: $showPairing) {
            PairingSheet(onPaired: {
                showPairing = false
                accountSession = GrantTapAccountAPI.session
                model.refreshAccountDeviceCatalog()
                model.startAccountSpaceSync(force: true)
                Task { await loadAccountDevices(force: true) }
            }).environmentObject(model)
        }
        .sheet(isPresented: $showControllerInvite) {
            ControllerNetworkInviteSheet(initialMachineId: inviteMachineId)
                .environmentObject(model)
        }
        .confirmationDialog(L("Unlink all computers?"),
                            isPresented: $showForgetConfirmation,
                            titleVisibility: .visible) {
            Button(L("Unlink all"), role: .destructive) { model.forgetPairing() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This removes every linked computer and local session state from this iPhone."))
        }
    }

    private func isOnline(_ computer: AccountComputer) -> Bool {
        AccountComputerChatStatus.isOnline(computer,
            nowMs: Date().timeIntervalSince1970 * 1_000)
    }

    private func accountComputerStatus(_ computer: AccountComputer) -> String {
        if accountComputerHasChats(computer) { return L("Chats available") }
        guard isOnline(computer) else { return L("Offline") }
        #if targetEnvironment(macCatalyst)
        return L("Online")
        #else
        let links = model.connectionRegistry.connections.filter { $0.linkedMachineId == computer.id }
        let activeRooms = Set(links.compactMap { model.relaysByRoom[$0.id]?.task == nil ? nil : $0.id })
        return AccountComputerChatStatus.label(online: true, hasChats: false, links: links,
            allowsManagedTransport: subscription.allowsManagedTransport, activeRooms: activeRooms)
        #endif
    }

    private func accountComputerHasChats(_ computer: AccountComputer) -> Bool {
        let links = model.connectionRegistry.connections.filter { $0.linkedMachineId == computer.id }
        return AccountComputerChatStatus.hasChats(links) {
            model.snapshotForConnection($0).phase == .live
        }
    }

    #if !targetEnvironment(macCatalyst)
    private func needsRelayVerification(_ computer: AccountComputer) -> Bool {
        guard isOnline(computer), !subscription.allowsManagedTransport else { return false }
        return model.connectionRegistry.connections.contains { connection in
            connection.linkedMachineId == computer.id
                && DeviceEndpointDirectory.isManaged(connection.pairing.relayUrl)
                && connection.pairing.directoryUrl == nil
        }
    }

    private func retryAccountComputer(_ computer: AccountComputer) async {
        let room = model.connectionRegistry.connections.first {
            $0.linkedMachineId == computer.id
        }?.id
        if let room { await model.reconnectConnection(roomId: room) }
        else { model.startAccountSpaceSync(force: true) }
        await loadAccountDevices()
    }
    #endif

    private var linkLocalAccount: ((GrantTapAccountSession) async throws -> Void)? {
        #if targetEnvironment(macCatalyst)
        guard localComputer != nil else { return nil }
        return { session in
            try await MacNativeAccess.shared.linkAccount(session.token)
            await localMCP.refresh()
            accountSession = session
            await loadAccountDevices()
        }
        #else
        return nil
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private func linkCurrentMac() async {
        guard let session = accountSession, let linkLocalAccount, !localLinkBusy else { return }
        localLinkBusy = true
        localLinkError = nil
        defer { localLinkBusy = false }
        do { try await linkLocalAccount(session) }
        catch { localLinkError = error.localizedDescription }
    }
    #endif

    private func loadAccountDevices(force: Bool = false) async {
        let session = GrantTapAccountAPI.session
        accountSession = session
        let previousIDs = Set(roster.computers.map(\.id))
        await roster.refresh(session: session, force: force)
        #if !targetEnvironment(macCatalyst)
        if session != nil {
            let discoveredOnlineMac = roster.computers.contains {
                !previousIDs.contains($0.id) && isOnline($0)
            }
            model.startAccountSpaceSync(force: force || discoveredOnlineMac)
        }
        #endif
    }
}
