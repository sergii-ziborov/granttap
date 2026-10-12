import Combine
import Foundation

@MainActor
extension SubscriptionStore {
    var transportAccessChanges: AnyPublisher<Void, Never> {
        Publishers.Merge3($entitlement.map { _ in () },
                          $betaRelayAccess.map { _ in () },
                          $accountBetaGrant.map { _ in () })
            .eraseToAnyPublisher()
    }

    /// A tester grant is a separate, expiring account entitlement.
    func refreshBetaRelayAccess() async {
        do {
            applyAccountGrant(try await accountBetaLoader())
        } catch {
            if (accountBetaGrant?.expiresAt ?? .distantPast) <= clock() {
                applyAccountGrant(nil)
            }
        }
        if !accountGrantAllowsTransport, !betaRelayAccess, await betaEnvironmentLoader() {
            betaRelayAccess = true
        }
        lastTransportCheckAt = clock()
    }

    /// Avoid an App Store prompt when the signed-in account already has tester access.
    func verifyBetaRelayAccess() async {
        betaVerificationError = nil
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
              !allowsManagedTransport || accountBetaGrant != nil else { return }
        await refreshBetaRelayAccess()
        if !allowsManagedTransport { await refresh() }
    }

    private func applyAccountGrant(_ grant: AccountBetaRelayGrant?) {
        if accountBetaGrant != grant { accountBetaGrant = grant }
    }
}
