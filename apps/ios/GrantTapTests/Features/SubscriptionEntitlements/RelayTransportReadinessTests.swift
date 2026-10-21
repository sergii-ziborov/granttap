import XCTest
@testable import GrantTap

@MainActor
final class RelayTransportReadinessTests: XCTestCase {
    func testVerifiedDistributionOpensBeforeSlowAccountServiceAndSharesTheLookup() async {
        var accountReply: CheckedContinuation<AccountSubscriptionGrant?, Never>?
        var accountReads = 0
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in [] },
            betaEnvironmentLoader: { true }, accountBetaLoader: { nil },
            accountSubscriptionLoader: {
                accountReads += 1
                return await withCheckedContinuation { accountReply = $0 }
            })
        let ready = expectation(description: "Verified local evidence opens without an account response")
        let connection = Task { @MainActor in
            let allowed = await store.connectionTransportAccess()
            XCTAssertTrue(allowed)
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertTrue(store.betaRelayAccess)
        XCTAssertEqual(accountReads, 1)
        accountReply?.resume(returning: nil)
        await connection.value
    }

    func testValidEvidenceDoesNotBlockConnectionOnRevalidation() async {
        var accountReply: CheckedContinuation<AccountSubscriptionGrant?, Never>?
        var reads = 0
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in [] },
            betaEnvironmentLoader: { false }, accountBetaLoader: { nil },
            accountSubscriptionLoader: {
                reads += 1
                if reads > 1 { return nil }
                return await withCheckedContinuation { accountReply = $0 }
            },
            currentAccountID: { "fixture" })
        store.accountBetaGrant = .init(accountID: "fixture", expiresAt: Date().addingTimeInterval(60))
        let allowed = await store.connectionTransportAccess()
        XCTAssertTrue(allowed)
        await Task.yield()
        accountReply?.resume(returning: nil)
        await store.transportRevalidation?.value
        XCTAssertFalse(store.allowsManagedTransport, "Confirmed account revocation still takes effect")
    }

    func testUnverifiedEvidenceCannotOpenManagedTransport() async {
        let store = SubscriptionStore(startObserving: false, snapshotLoader: { _ in [] },
            betaEnvironmentLoader: { false }, accountBetaLoader: { nil }, accountSubscriptionLoader: { nil })
        let allowed = await store.connectionTransportAccess()
        XCTAssertFalse(allowed)
    }
}
