import Combine
import Foundation

@MainActor
extension SubscriptionStore {
    var hasTestingAccess: Bool { betaRelayAccess || accountGrantAllowsTransport }

    var transportAccessChanges: AnyPublisher<Void, Never> {
        Publishers.CombineLatest4($entitlement, $betaRelayAccess,
                                  $accountBetaGrant, $accountSubscriptionGrant)
            .map { entitlement, beta, grant, subscription in
                let account = self.currentAccountID()
                let now = self.clock()
                return beta || entitlement.state.allowsRemoteInfrastructure
                    || grant.map { $0.accountID == account && $0.expiresAt > now } == true
                    || subscription?.allowsTransport(accountID: account, now: now) == true
            }
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// A tester grant is a separate, expiring account entitlement.
    func refreshAccountTransportAccess() async {
        await refreshAccountSubscription()
        if accountSubscriptionAllowsTransport {
            lastTransportCheckAt = clock()
            return
        }
        do {
            applyAccountGrant(try await accountBetaLoader())
        } catch {
            if (accountBetaGrant?.expiresAt ?? .distantPast) <= clock() {
                applyAccountGrant(nil)
            }
        }
        lastTransportCheckAt = clock()
    }

    func refreshBetaRelayAccess() async {
        await refreshAccountTransportAccess()
        if accountSubscriptionAllowsTransport { return }
        if !accountGrantAllowsTransport, !betaRelayAccess, await betaEnvironmentLoader() {
            betaRelayAccess = true
        }
        lastTransportCheckAt = clock()
    }

    /// Avoid an App Store prompt when the signed-in account already has tester access.
    func verifyBetaRelayAccess() async {
        betaVerificationError = nil
        await refreshAccountSubscription()
        if accountSubscriptionAllowsTransport { return }
        do {
            applyAccountGrant(try await accountBetaLoader())
        } catch {
            if !accountGrantAllowsTransport { betaVerificationError = error.localizedDescription }
        }
        if !accountGrantAllowsTransport {
            do {
                let verified = try await betaEnvironmentRefresh()
                if betaRelayAccess != verified { betaRelayAccess = verified }
                if !allowsManagedTransport {
                    betaVerificationError = L("App Store could not verify beta relay access.")
                } else {
                    betaVerificationError = nil
                }
            } catch {
                betaVerificationError = error.localizedDescription
            }
        }
        lastTransportCheckAt = clock()
    }

    /// Refresh account grants even while valid so server revocation takes effect.
    func recheckTransportIfNeeded(now: Date = Date()) async {
        guard lastTransportCheckAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true,
              !allowsManagedTransport || accountBetaGrant != nil || accountSubscriptionGrant != nil else { return }
        await refreshBetaRelayAccess()
        if !allowsManagedTransport { await refresh() }
    }

    private func applyAccountGrant(_ grant: AccountBetaRelayGrant?) {
        if accountBetaGrant != grant { accountBetaGrant = grant }
    }

    func refreshAccountSubscription() async {
        do {
            let grant = try await accountSubscriptionLoader()
            if accountSubscriptionGrant != grant { accountSubscriptionGrant = grant }
        } catch {
            if !accountSubscriptionAllowsTransport { accountSubscriptionGrant = nil }
        }
    }
}
