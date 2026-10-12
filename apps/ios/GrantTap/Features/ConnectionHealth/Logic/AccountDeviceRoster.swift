import SwiftUI

/// Keeps the last known account devices visible while a fresh catalog is fetched.
@MainActor
final class AccountDeviceRoster: ObservableObject {
    typealias Loader = @MainActor (GrantTapAccountSession) async throws -> [AccountComputer]

    @Published private(set) var computers: [AccountComputer] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let load: Loader
    private var requestID = UUID()
    private var displayedAccountID: String?

    init(load: @escaping Loader = { try await AccountRecovery.computers(session: $0) }) {
        self.load = load
    }

    func clear() {
        requestID = UUID()
        displayedAccountID = nil
        computers = []
        error = nil
        isLoading = false
    }

    func refresh(session: GrantTapAccountSession?, force: Bool = false,
                 currentSession: @escaping @MainActor () -> GrantTapAccountSession? = {
                     GrantTapAccountAPI.session
                 }) async {
        guard let session else { clear(); return }
        if displayedAccountID != session.accountId {
            clear()
            displayedAccountID = session.accountId
        }
        if isLoading && !force { return }
        let request = UUID()
        requestID = request
        isLoading = true
        error = nil
        defer { if requestID == request { isLoading = false } }
        do {
            let latest = try await load(session)
            let active = currentSession()
            guard requestID == request,
                  active?.accountId == session.accountId,
                  active?.token == session.token else { return }
            computers = latest
        } catch is CancellationError {
            return
        } catch {
            let active = currentSession()
            guard requestID == request,
                  active?.accountId == session.accountId,
                  active?.token == session.token else { return }
            self.error = L("Could not load devices. Tap to retry.")
        }
    }
}
