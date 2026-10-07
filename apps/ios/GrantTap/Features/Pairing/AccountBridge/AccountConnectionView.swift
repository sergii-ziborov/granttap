import SwiftUI

struct AccountConnectionView: View {
    var embedded = false
    var onLinkLocal: ((GrantTapAccountSession) async throws -> Void)? = nil
    var onAccountReady: (() -> Void)? = nil
    var onAccountSignedOut: (() -> Void)? = nil
    var onAccountDeleted: ((String) throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var session = GrantTapAccountAPI.session
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDeletion = false

    var body: some View {
        Group {
            if embedded {
                accountControls
                    .task { if let session { await refresh(session) } }
            } else {
                #if targetEnvironment(macCatalyst)
                accountPage.pageNavigationTitle(L("Connect with passkey"))
                #else
                CompatNavigationStack {
                    accountPage
                        .navigationTitle(L("Connect with passkey"))
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button(L("Done")) { dismiss() }
                        } }
                }
                #endif
            }
        }
        .confirmationDialog(L("Delete GrantTap account?"),
                            isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button(L("Delete account"), role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text(L("This removes passkey recovery and linked computers from your account. QR pairings on this device remain. Apple subscriptions continue until canceled separately."))
        }
    }

    private var accountPage: some View {
        ScrollView {
            #if targetEnvironment(macCatalyst)
            HStack(alignment: .top, spacing: 44) {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.claude)
                    Text(L("Connect with passkey"))
                        .font(.system(size: 28, weight: .bold))
                    Text(L("Use the same passkey provider on Mac and iPhone. Apple Passwords syncs through iCloud; other providers may require your phone."))
                        .font(.body).foregroundStyle(Theme.muted)
                    Text(L("Your Account Mesh is available even before any computer is added."))
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: 330, alignment: .leading)
                accountControls
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            .frame(maxWidth: 1060, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .top)
            #else
            VStack(alignment: .leading, spacing: 16) {
                Text(L("A passkey opens your Account Mesh on the relay. You can sign in before adding any computer."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Text(L("Choose Apple Passwords when creating a passkey to sync it through iCloud, or use your chosen provider on each device."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                accountControls
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(20)
            #endif
        }
        .background(Theme.bg)
        .task { if let session { await refresh(session) } }
    }

    private var accountControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let session {
                Label(L("GrantTap account connected"), systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(Theme.ok)
                Text(L("Your account contains your Projects and their Meshes. Each Task keeps its own computer route."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Text(String(format: L("Account %@"), String(session.accountId.prefix(8))))
                    .font(.caption).foregroundStyle(Theme.muted)
                Button(L("Use a different passkey")) {
                    onAccountSignedOut?()
                    GrantTapAccountAPI.clearSession()
                    self.session = nil
                }.disabled(busy)
                Link(L("Manage Apple subscription"),
                     destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Button(L("Delete account"), role: .destructive) {
                    confirmingDeletion = true
                }.disabled(busy)
            } else {
                Button(L("Sign in with passkey")) { Task { await authenticate(register: false) } }
                    .buttonStyle(FilledButton(tint: Theme.claude))
                    .disabled(busy)
                Button(L("Create a GrantTap account")) { Task { await authenticate(register: true) } }
                    .buttonStyle(OutlineButton())
                    .disabled(busy)
            }
            if busy {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L("Connecting…"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
            }
            if let error { Text(error).foregroundStyle(Theme.riskHigh).font(.footnote) }
        }
    }

    private func authenticate(register: Bool) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let signedIn = try await GrantTapAccountAPI.authenticate(register: register)
            session = signedIn
            onAccountReady?()
            await refresh(signedIn)
        } catch {
            self.error = AccountBridgeError.presentationMessage(for: error)
        }
    }

    private func deleteAccount() async {
        guard let current = session else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await GrantTapAccountAPI.deleteAccount(current)
            onAccountSignedOut?()
            session = nil
            try onAccountDeleted?(current.accountId)
        } catch { self.error = error.localizedDescription }
    }

    private func refresh(_ session: GrantTapAccountSession) async {
        guard let onLinkLocal else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await onLinkLocal(session) }
        catch { self.error = error.localizedDescription }
    }
}
