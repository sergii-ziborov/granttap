import SwiftUI

struct AccountConnectionView: View {
    let onPaired: (Pairing) -> Bool
    var allowsRecovery = true
    @Environment(\.dismiss) private var dismiss
    @State private var session = GrantTapAccountAPI.session
    @State private var computers: [AccountComputer] = []
    @State private var busy = false
    @State private var error: String?
    @State private var recoveryTask: Task<Void, Never>?

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("A passkey can find your linked computers when their Mac service is online. Pairing keys travel encrypted directly to this device."))
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    if let session {
                        Text(String(format: L("Account %@"), String(session.accountId.prefix(8))))
                            .font(.caption).foregroundStyle(Theme.muted)
                        ForEach(allowsRecovery ? computers : []) { computer in
                            Button {
                                recoveryTask?.cancel()
                                recoveryTask = Task { await connect(computer, session: session) }
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                    VStack(alignment: .leading) {
                                        Text(computer.name)
                                        Text(computer.lastSeenAt == nil
                                             ? L("Waiting for this Mac")
                                             : L("Account-linked Mac"))
                                            .font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .buttonStyle(OutlineButton())
                            .disabled(busy)
                        }
                        if !allowsRecovery {
                            ForEach(computers) { computer in
                                Label(computer.name, systemImage: "desktopcomputer")
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        if computers.isEmpty && !busy {
                            Text(L("No Mac is linked to this account yet. Sign in with the same passkey on your Mac or its MCP connection page."))
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Button(L("Refresh computers")) { Task { await refresh(session) } }
                            .disabled(busy)
                        Button(L("Use a different passkey")) {
                            GrantTapAccountAPI.clearSession()
                            self.session = nil
                            computers = []
                        }.disabled(busy)
                    } else {
                        Button(L("Sign in with passkey")) { Task { await authenticate(register: false) } }
                            .buttonStyle(FilledButton(tint: Theme.claude))
                            .disabled(busy)
                        Button(L("Create a GrantTap account")) { Task { await authenticate(register: true) } }
                            .buttonStyle(OutlineButton())
                            .disabled(busy)
                    }
                    if busy { ProgressView(L("Connecting…")) }
                    if let error { Text(error).foregroundStyle(Theme.riskHigh).font(.footnote) }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle(L("Connect with passkey"))
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            } }
            .task { if let session { await refresh(session) } }
            .onDisappear { recoveryTask?.cancel() }
        }
    }

    private func authenticate(register: Bool) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let signedIn = try await GrantTapAccountAPI.authenticate(register: register)
            session = signedIn
            await refresh(signedIn)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh(_ session: GrantTapAccountSession) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            #if targetEnvironment(macCatalyst)
            try await MacNativeAccess.shared.linkAccount(session.token)
            #endif
            computers = try await AccountRecovery.computers(session: session)
        }
        catch { self.error = error.localizedDescription }
    }

    private func connect(_ computer: AccountComputer, session: GrantTapAccountSession) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let pairing = try await AccountRecovery.connect(computer, session: session)
            if onPaired(pairing) { dismiss() }
            else { error = AppModel.pairingStorageFailureMessage }
        } catch is CancellationError {
            return
        } catch { self.error = error.localizedDescription }
    }
}
