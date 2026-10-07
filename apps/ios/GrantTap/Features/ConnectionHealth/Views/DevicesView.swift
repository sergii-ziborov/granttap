import SwiftUI

/// The account-wide Mesh exists independently of computers and Project Meshes.
/// Adding a device only contributes an execution route to that account.
struct DevicesView: View {
    @EnvironmentObject private var model: AppModel
    var localComputer: String?
    var localAccountLinked: Bool?
    var localPaired: Bool?
    var localRelayStatus: String?
    var localPhoneReachability: String?
    @State private var showPairing = false
    @State private var showControllerInvite = false
    @State private var showForgetConfirmation = false
    @State private var accountSession = GrantTapAccountAPI.session
    @State private var accountComputers: [AccountComputer] = []
    @State private var rosterLoading = false
    @State private var rosterError: String?
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
                        model.startAccountSpaceSync(force: true)
                    },
                    onAccountSignedOut: {
                        accountSession = nil
                        accountComputers = []
                        model.stopAccountSpaceSync()
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
                    if rosterLoading {
                        ProgressView(L("Loading devices…"))
                    } else if let rosterError {
                        Button(rosterError) { Task { await loadAccountDevices() } }
                    } else if accountComputers.isEmpty {
                        Text(L("No devices yet. Your Account Mesh is ready."))
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(accountComputers) { computer in
                            HStack {
                                Label(computer.name, systemImage: "desktopcomputer")
                                Spacer()
                                Text(isOnline(computer) ? L("Online") : L("Offline"))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }

            #if targetEnvironment(macCatalyst)
            if accountSession != nil {
                Section(L("This Mac")) {
                    Label(localAccountLinked == true
                          ? L("MCP account link saved")
                          : L("Link this Mac to your Account Mesh"),
                          systemImage: localAccountLinked == true
                            ? "checkmark.circle.fill" : "desktopcomputer.and.arrow.down")
                    if localAccountLinked != true, localComputer != nil {
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
                onInviteController: { showControllerInvite = true },
                onForgetAll: { showForgetConfirmation = true },
                localComputer: localComputer
            )
            #endif
        }
        .pageNavigationTitle(L("Devices"), showsBack: false)
        .accessibilityIdentifier("devices.page")
        .task(id: accountSession?.accountId) { await loadAccountDevices() }
        #if targetEnvironment(macCatalyst)
        .task(id: localComputer) {
            if accountSession != nil, localComputer != nil, localAccountLinked != true {
                await linkCurrentMac()
            }
        }
        #endif
        .sheet(isPresented: $showPairing) { PairingSheet().environmentObject(model) }
        .sheet(isPresented: $showControllerInvite) {
            ControllerNetworkInviteSheet().environmentObject(model)
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
        guard let seen = computer.lastSeenAt else { return false }
        return Date().timeIntervalSince1970 * 1_000 - seen < 120_000
    }

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

    private func loadAccountDevices() async {
        guard let session = accountSession else { return }
        rosterLoading = true
        rosterError = nil
        defer { rosterLoading = false }
        do {
            let computers = try await AccountRecovery.computers(session: session)
            guard GrantTapAccountAPI.session?.accountId == session.accountId else { return }
            accountComputers = computers
        } catch {
            guard GrantTapAccountAPI.session?.accountId == session.accountId else { return }
            rosterError = L("Could not load devices. Tap to retry.")
        }
    }
}
